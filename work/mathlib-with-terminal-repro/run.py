#!/usr/bin/env python3
"""Guarded, artifact-pinned diagnostics for the WithTerminal 11,422,301 failure."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

GENERATION = ROOT / 'work/mathlib-alignment-5m-20260913'
TARGET = 11422301


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--prefix', type=Path, action='append', default=[])
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--entries', action='store_true')
    parser.add_argument('--trace-call', type=int)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    directory = args.directory.resolve()
    if directory.parent != HERE or directory.exists():
        raise ValueError('Expected a new diagnostic directory')
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    importer = Path(profile['importer'])
    consumer = os.environ.get('ROCQ_ALIGNMENT_IMPORTER')
    if consumer:
        importer = Path(consumer).resolve(strict=True)
        if importer.parent != ROOT / 'work/kernel-alignment-pass' or not importer.name.startswith('importer.'):
            raise ValueError('Expected an isolated consumer importer')
    direct.checking.IMPORTER = importer
    inputs = {str(p): chunks.sha(p) for p in (source, chunks.WORKER, Path(__file__), plan_path)}
    if consumer:
        for path in (importer / 'src').iterdir():
            if path.suffix in ('.ml', '.mli', '.mlg', '.cmxs') or path.name.startswith('META'):
                inputs[str(path)] = chunks.sha(path)
    for path in re.findall(r'Lean Import "([^"]+)"', source.read_text()):
        inputs[path] = chunks.sha(Path(path))
    with (chunks.OLD_RUN / 'launcher.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        chunks.check_entries(profile['inputs'])
        inputs.update(profile['inputs'])
        if not args.native:
            predecessors = [c for c in plan['chunks'] if c['end'] <= 10000001]
            if not predecessors or predecessors[-1]['end'] != 10000001:
                raise ValueError('Expected the complete 10M checkpoint chain')
            for chunk in predecessors:
                if chunks.verify_saved(plan_path.parent, chunk) is None:
                    raise ValueError('Missing sealed checkpoint: ' + chunk['module'])
                for suffix in ('.v', '.vo'):
                    path = plan_path.parent / (chunk['module'] + suffix)
                    inputs[str(path)] = chunks.sha(path)
            inputs[plan['export']] = plan['export_sha256']
        extra = []
        for prefix in args.prefix:
            prefix = prefix.resolve(strict=True)
            record = json.loads((prefix / 'result.json').read_text())
            artifact = prefix / (record['module'] + '.vo')
            if record['exit_code'] or chunks.sha(artifact) != record['vo_sha256']:
                raise ValueError('Unverified diagnostic ancestor')
            for path in (prefix / 'result.json', artifact, artifact.with_suffix('.v')):
                inputs[str(path)] = chunks.sha(path)
            extra.extend(['-Q', str(prefix), ''])
        chunks.check_entries(inputs)
        chunks.check_disk(HERE)
        directory.mkdir()
        target = directory / source.name
        shutil.copy2(source, target)
        env = direct.environment(16384)
        env.update(LEAN_IMPORT_DECLARE_TRACE_LINE=str(TARGET),
                   LEAN_IMPORT_EXCEPTION_BACKTRACE='1', LEAN_IMPORT_CHECKPOINT_STATS='1')
        if args.entries:
            env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
        if args.trace_call is not None:
            env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
        command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '3600s',
                   str(chunks.WORKER), '--kind=compile', '-coqlib', env['COQLIB'],
                   '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
                   '-Q', str(GENERATION / 'foundation'), 'LeanImport', '-I', str(importer / 'src'),
                   *extra, '-Q', str(plan_path.parent), '', '-Q', str(directory), '', str(target)]
        chunks.save_json(directory / 'invocation.json', {'command': command, 'inputs': inputs})
        print(directory, flush=True)
        started = time.monotonic()
        with (directory / 'run.log').open('x') as log:
            result = subprocess.run(command, cwd=directory, env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
        chunks.check_entries(inputs)
        record = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
                  'module': target.stem, 'worker_sha256': inputs[str(chunks.WORKER)]}
        if not result.returncode:
            record['vo_sha256'] = chunks.sha(target.with_suffix('.vo'))
        chunks.save_json(directory / 'result.json', record)
        print(json.dumps(record), flush=True)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
