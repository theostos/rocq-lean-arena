#!/usr/bin/env python3
"""Pinned, guarded replay of the 5,816,190 regression; never promotes snapshots."""
import argparse
import fcntl
from functools import lru_cache
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

GENERATION = ROOT / 'work/mathlib-alignment-5m-20260912'
TARGET = 5816190


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--prefix', type=Path, action='append', default=[],
                        help='Verified diagnostic ancestor; repeat for transitive dependencies')
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--entries', action='store_true')
    parser.add_argument('--trace-call', type=int)
    parser.add_argument('--dump', action='store_true')
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    directory = args.directory.resolve()
    if directory.parent != HERE or directory.exists():
        raise ValueError('Expected a new diagnostic directory')
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    importer = Path(profile['importer'])
    direct.checking.IMPORTER = importer
    worker = chunks.WORKER
    inputs = {str(p): chunks.sha(p) for p in (source, worker, Path(__file__), plan_path)}
    for path in re.findall(r'Lean Import "([^"]+)"', source.read_text()):
        inputs[path] = chunks.sha(Path(path))
    with (chunks.OLD_RUN / 'launcher.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        chunks.check_entries(profile['inputs'])
        inputs.update(profile['inputs'])
        if not args.native:
            chunk = plan['chunks'][0]
            if chunk['end'] != 5000001 or chunks.verify_saved(plan_path.parent, chunk) is None:
                raise ValueError('Missing validated 5M checkpoint')
            inputs[str(Path(plan['export']))] = plan['export_sha256']
            for suffix in ('.v', '.vo'):
                path = plan_path.parent / (chunk['module'] + suffix)
                inputs[str(path)] = chunks.sha(path)
        extra = []
        for prefix_arg in args.prefix:
            prefix = prefix_arg.resolve(strict=True)
            result_path = prefix / 'result.json'
            result = json.loads(result_path.read_text())
            artifact = prefix / (result['module'] + '.vo')
            if result['exit_code'] or chunks.sha(artifact) != result['vo_sha256']:
                raise ValueError('Unverified diagnostic prefix')
            for path in (result_path, artifact, artifact.with_suffix('.v')):
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
        if args.dump:
            env['LEAN_IMPORT_DUMP_CURRENT_DEF'] = str(TARGET)
        command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '2400s',
                   str(worker), '--kind=compile', '-coqlib', env['COQLIB'],
                   '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
                   '-Q', str(GENERATION / 'foundation'), 'LeanImport',
                   '-I', str(importer / 'src'), *extra,
                   '-Q', str(plan_path.parent), '', '-Q', str(directory), '', str(target)]
        chunks.save_json(directory / 'invocation.json', {'command': command, 'inputs': inputs})
        print(directory, flush=True)
        started = time.monotonic()
        with (directory / 'run.log').open('x') as log:
            result = subprocess.run(command, cwd=directory, env=env,
                                    stdout=log, stderr=subprocess.STDOUT)
        chunks.check_entries(inputs)
        record = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
                  'module': target.stem, 'worker_sha256': inputs[str(worker)]}
        if not result.returncode:
            record['vo_sha256'] = chunks.sha(target.with_suffix('.vo'))
        chunks.save_json(directory / 'result.json', record)
        print(json.dumps(record), flush=True)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
