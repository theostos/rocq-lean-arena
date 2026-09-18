#!/usr/bin/env python3
"""Check the original target with controlled conversion strategies."""
import argparse
import fcntl
from functools import lru_cache
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lazy-prefix', action='store_true')
    parser.add_argument('--prepare-prefix', action='store_true')
    parser.add_argument('--prefix', type=Path)
    parser.add_argument('--strategy', choices=['default', 'projection-first', 'no-dependency-first', 'no-direct-arguments', 'expand-first', 'substitution-memo', 'rigid-left-first'], default='default')
    parser.add_argument('--line-timeout', type=int, default=120)
    parser.add_argument('--trace-call', type=int)
    parser.add_argument('--memo-limit', type=int)
    parser.add_argument('--print-reference', action='append', default=[])
    parser.add_argument('--worker', type=Path, default=chunks.WORKER)
    args = parser.parse_args()
    if sum((args.lazy_prefix, args.prepare_prefix, args.prefix is not None)) > 1:
        parser.error('Choose only one prefix mode')
    if not 1 <= args.line_timeout <= 1800:
        parser.error('Line timeout must be between 1 and 1800 seconds')
    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        directory = ROOT / 'work/mathlib-ndjson/checkpoints'
        plan = json.loads((directory / 'plan.json').read_text())
        chunks.sha = lru_cache(maxsize=None)(chunks.sha)
        chunks.check_entries(chunks.generation_toolchain(plan)['inputs'])
        if chunks.sha(Path(plan['export'])) != plan['export_sha256']:
            raise RuntimeError('Export changed')
        ancestors = [c for c in plan['chunks'] if c['end'] <= 9_000_001]
        for chunk in ancestors:
            if chunks.verify_saved(directory, chunk) is None:
                raise RuntimeError('Missing checkpoint: ' + chunk['module'])
        chunks.check_disk(HERE, directory / 'MathlibTo9000000.vo')
        stage = Path(tempfile.mkdtemp(prefix='focus-' + args.strategy + '-', dir=HERE))
        source = '''From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Require Import MathlibTo9000000.
'''
        source += f'Set Lean Line Timeout {args.line_timeout}.\n'
        extra_paths = []
        inputs = [args.worker, direct.checking.IMPORTER / 'src/lean_import.cmxs', Path(plan['export'])]
        if args.prefix:
            prefix = args.prefix.resolve()
            saved = json.loads((prefix / 'result.json').read_text())
            if saved['exit_code'] != 0 or chunks.sha(prefix / 'MathlibTo10000000.vo') != saved.get('vo_sha256'):
                raise RuntimeError('Prefix did not finish checking')
            metadata = json.loads((prefix / 'invocation.json').read_text())
            if not metadata.get('prepare_prefix'):
                raise RuntimeError('Not a checked pre-target prefix')
            if metadata['inputs'][str(Path(plan['export']))] != plan['export_sha256']:
                raise RuntimeError('Prefix export mismatch')
            for filename, digest in metadata['inputs'].items():
                if filename != metadata['worker'] and chunks.sha(Path(filename)) != digest:
                    raise RuntimeError('Prefix input changed: ' + filename)
            source += (f'Require Import MathlibTo10000000.\n'
                       f'Set Lean Line Timeout {args.line_timeout}.\n'
                       f'Lean Import "{plan["export"]}" 9239031 9239032.\n')
            extra_paths = ['-Q', str(prefix), '']
            inputs.append(prefix / 'MathlibTo10000000.vo')
        elif args.print_reference:
            pass
        elif args.prepare_prefix:
            source += f'Lean Import "{plan["export"]}" 9000001 9239031.\n'
        elif args.lazy_prefix:
            source += (f'Set Lean Lazy Instantiation.\nLean Import "{plan["export"]}" 9000001 9239031.\n'
                       f'Unset Lean Lazy Instantiation.\nLean Import "{plan["export"]}" 9239031 9239032.\n')
        else:
            source += f'Lean Import "{plan["export"]}" 9000001 9239032.\n'
        if args.print_reference:
            if args.prefix:
                source = source.rsplit('Lean Import', 1)[0]
            source += 'Set Printing Depth 40.\n'
            for reference in args.print_reference:
                if not re.fullmatch(r'[A-Za-z0-9_.]+', reference):
                    parser.error('Invalid reference')
                source += f'Print {reference}.\n'
        path = stage / ('Inspect.v' if args.print_reference else 'Target.v' if args.prefix else 'MathlibTo10000000.v')
        path.write_text(source)
        env = direct.environment(8192)
        env.update(LEAN_IMPORT_DECLARE_TRACE_LINE='9239031', LEAN_IMPORT_EXCEPTION_BACKTRACE='1',
                   LEAN_IMPORT_CHECKPOINT_STATS='1', ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES='1')
        if args.strategy != 'default':
            env['ROCQ_DIAGNOSTIC_' + args.strategy.upper().replace('-', '_')] = '1'
        if args.trace_call is not None:
            env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
        if args.memo_limit is not None:
            if not 1 <= args.memo_limit <= 1_048_576:
                parser.error('Memo limit must be between 1 and 1,048,576')
            env['ROCQ_DIAGNOSTIC_CONVERSION_MEMO_LIMIT'] = str(args.memo_limit)
        if os.environ.get('ROCQ_MEMORY_OWNER_SERVICE'):
            env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
        command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '7200s',
                   str(args.worker.resolve()), '--kind=compile', '-coqlib', env['COQLIB'], '-q', '-bytecode-compiler', 'no',
                   '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(directory), '',
                   '-Q', str(ROOT / 'work/mathlib-ndjson/foundation'), 'LeanImport',
                   '-I', str(direct.checking.IMPORTER / 'src'), *extra_paths, '-Q', str(stage), '', str(path)]
        inputs += [directory / (c['module'] + '.vo') for c in ancestors]
        (stage / 'invocation.json').write_text(json.dumps({'command': command, 'source': source,
            'strategy': args.strategy, 'lazy_prefix': args.lazy_prefix,
            'worker': str(args.worker),
            'memo_limit': args.memo_limit,
            'prepare_prefix': args.prepare_prefix, 'prefix': str(args.prefix) if args.prefix else None,
            'inputs': {str(p): chunks.sha(p) for p in inputs}}, indent=2) + '\n')
        print(stage, flush=True)
        with (stage / 'run.log').open('x') as log:
            result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        result_data = {'exit_code': result.returncode}
        if result.returncode == 0 and args.prepare_prefix:
            result_data['vo_sha256'] = chunks.sha(path.with_suffix('.vo'))
        (stage / 'result.json').write_text(json.dumps(result_data) + '\n')
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
