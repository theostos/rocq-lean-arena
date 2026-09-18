#!/usr/bin/env python3
"""Guarded replay of the 11M failure, without modifying canonical checkpoints."""
import argparse
import fcntl
from functools import lru_cache
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

TARGET = 11289804
CHECKPOINTS = ROOT / 'work/mathlib-ndjson/checkpoints'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['lazy', 'prefix', 'target', 'full'], default='lazy')
    parser.add_argument('--prefix', type=Path)
    parser.add_argument('--worker', type=Path, default=chunks.WORKER)
    parser.add_argument('--line-timeout', type=int, default=180)
    parser.add_argument('--memory-mib', type=int, default=16384)
    parser.add_argument('--gc', default='s=4M,o=80,i=15,a=2,v=0,b')
    parser.add_argument('--trace-call', type=int)
    parser.add_argument('--entries', action='store_true')
    parser.add_argument('--dependency-memory', action='store_true')
    parser.add_argument('--allocations', action='store_true')
    parser.add_argument('--end', type=int, default=TARGET + 1)
    parser.add_argument('--no-dependency-first', action='store_true')
    args = parser.parse_args()
    if not 256 <= args.memory_mib <= 16384 or not 1 <= args.line_timeout <= 1800:
        parser.error('Out-of-bounds resource limit')
    if (args.mode == 'target') != bool(args.prefix):
        parser.error('--prefix is required exactly for target mode')
    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        chunks.sha = lru_cache(maxsize=None)(chunks.sha)
        plan = json.loads((CHECKPOINTS / 'plan.json').read_text())
        chunks.check_entries(chunks.generation_toolchain(plan)['inputs'])
        if chunks.sha(plan['export']) != plan['export_sha256']:
            raise RuntimeError('Export changed')
        ancestors = [c for c in plan['chunks'] if c['end'] <= 11000001]
        for chunk in ancestors:
            if chunks.verify_saved(CHECKPOINTS, chunk) is None:
                raise RuntimeError('Missing validated ancestor: ' + chunk['module'])
        chunks.check_disk(HERE, CHECKPOINTS / 'MathlibTo11000000.vo')
        stage = Path(tempfile.mkdtemp(prefix=args.mode + '-', dir=HERE))
        source = chunks.SETTINGS + 'Require Import MathlibTo11000000.\n'
        source += f'Set Lean Line Timeout {args.line_timeout}.\n'
        extra = []
        inputs = [args.worker.resolve(), direct.checking.IMPORTER / 'src/lean_import.cmxs',
                  Path(plan['export']), Path(__file__).resolve()]
        inputs += [CHECKPOINTS / (c['module'] + '.vo') for c in ancestors]
        if args.mode == 'target':
            prefix = args.prefix.resolve()
            saved = json.loads((prefix / 'result.json').read_text())
            metadata = json.loads((prefix / 'invocation.json').read_text())
            if saved['exit_code'] != 0 or metadata['mode'] != 'prefix':
                raise RuntimeError('Not a checked prefix')
            if chunks.sha(prefix / 'Prefix.vo') != saved['vo_sha256']:
                raise RuntimeError('Prefix changed')
            for filename, digest in metadata['inputs'].items():
                if filename not in (metadata['worker'], str(Path(__file__).resolve())):
                    if chunks.sha(filename) != digest:
                        raise RuntimeError('Prefix input changed: ' + filename)
            source += 'Require Import Prefix.\n'
            source += f'Set Lean Line Timeout {args.line_timeout}.\n'
            extra = ['-Q', str(prefix), '']
            inputs.append(prefix / 'Prefix.vo')
        else:
            if args.mode == 'lazy':
                source += 'Set Lean Lazy Instantiation.\n'
            end = args.end if args.mode == 'full' else TARGET
            source += f'Lean Import "{plan["export"]}" 11000001 {end}.\n'
        if args.mode in ('lazy', 'target'):
            source += 'Unset Lean Lazy Instantiation.\n'
            source += f'Lean Import "{plan["export"]}" {TARGET} {args.end}.\n'
        module = {'prefix': 'Prefix', 'full': 'MathlibTo12000000'}.get(args.mode, 'Target')
        path = stage / (module + '.v')
        path.write_text(source)
        env = direct.environment(args.memory_mib)
        env.update(OCAMLRUNPARAM=args.gc, LEAN_IMPORT_DECLARE_TRACE_LINE=str(TARGET),
                   LEAN_IMPORT_CHECKPOINT_STATS='1', LEAN_IMPORT_EXCEPTION_BACKTRACE='1')
        if args.entries:
            env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
        if args.dependency_memory:
            env['ROCQ_DIAGNOSTIC_DEPENDENCY_MEMORY'] = '1'
        if args.allocations:
            env['ROCQ_DIAGNOSTIC_ALLOCATION'] = '1'
        if args.trace_call is not None:
            env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
        if args.no_dependency_first:
            env['ROCQ_DIAGNOSTIC_NO_DEPENDENCY_FIRST'] = '1'
        command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '3600s',
                   str(args.worker.resolve()), '--kind=compile', '-coqlib', env['COQLIB'],
                   '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
                   '-Q', str(CHECKPOINTS), '',
                   '-Q', str(ROOT / 'work/mathlib-ndjson/foundation'), 'LeanImport',
                   '-I', str(direct.checking.IMPORTER / 'src'), *extra,
                   '-Q', str(stage), '', str(path)]
        chunks.save_json(stage / 'invocation.json', {
            'mode': args.mode, 'source': source, 'command': command, 'gc': args.gc,
            'worker': str(args.worker.resolve()),
            'inputs': {str(p): chunks.sha(p) for p in inputs}})
        print(stage, flush=True)
        started = time.monotonic()
        with (stage / 'run.log').open('x') as log:
            result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        data = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started}
        if result.returncode == 0:
            data['vo_sha256'] = chunks.sha(path.with_suffix('.vo'))
        chunks.save_json(stage / 'result.json', data)
        print(json.dumps(data), flush=True)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
