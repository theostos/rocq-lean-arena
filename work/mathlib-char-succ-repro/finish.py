#!/usr/bin/env python3
"""Run the complete pinned validation, then resume only after every check passes.

This supervisor does not monitor the production loop. Resource admission and
per-declaration timeouts remain enforced by the existing runners.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from resource_queue import wait_for_memory

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
STATE = HERE / 'finish-status.json'


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def pin_inputs(worker_sha, checker_sha):
    kernel = ROOT / '_worktrees/rocq/compact-peano-view'
    worker = kernel / '_build/default/topbin/rocqworker.exe'
    checker = kernel / '_build/default/checker/rocqchk.exe'
    if digest(worker) != worker_sha or digest(checker) != checker_sha:
        raise RuntimeError('The candidate binaries changed before admission')
    paths = [worker, checker]
    for folder in (kernel / 'kernel', kernel / 'checker',
                   kernel / 'test-suite/success', kernel / 'test-suite/unit-tests/kernel',
                   HERE, HERE.parent / 'kernel-alignment-pass'):
        paths.extend(path for path in folder.iterdir()
                     if path.is_file() and path.suffix in {'.ml', '.mli', '.py', '.sh', '.v'})
    return {path: digest(path) for path in paths}


def status(phase, **details):
    record = {'phase': phase, 'updated_unix': time.time(), **details}
    temporary = STATE.with_suffix('.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(STATE)
    print(json.dumps(record), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker-sha', required=True)
    parser.add_argument('--checker-sha', required=True)
    args = parser.parse_args()
    if STATE.exists() or (HERE / 'validation-v13').exists():
        raise RuntimeError('A validation attempt already exists; inspect it first')
    inputs = pin_inputs(args.worker_sha, args.checker_sha)
    # Each validation stage now waits for its own budget. Small checks can
    # proceed while the large replay waits for 16 GiB plus the 3 GiB reserve.
    if any(digest(path) != expected for path, expected in inputs.items()):
        status('failed', step='admission', reason='Candidate inputs changed while queued')
        return 1
    status('validating', worker_sha256=args.worker_sha,
           checker_sha256=args.checker_sha, progress=str(HERE / 'validation-v13/progress.json'),
           max_memory_mib=16384, reserve_mib=3072)
    steps = [
        ('validation', [HERE / 'validate.py', '--worker-sha', args.worker_sha,
                        '--checker-sha', args.checker_sha]),
        ('promotion_check', [HERE / 'resume.py', '--validate-only']),
        ('resume', [HERE / 'resume.py']),
    ]
    for phase, command in steps:
        if phase == 'resume':
            wait_for_memory(16384, lambda **memory:
                status('waiting_for_memory', step='resume', **memory))
        result = subprocess.run([sys.executable, *map(str, command)], cwd=ROOT)
        if result.returncode:
            status('failed', step=phase, exit_code=result.returncode,
                   launch_attempted=phase == 'resume')
            return result.returncode
    # One startup observation, not recurring production monitoring.
    unit = 'rocq-mathlib-alignment-5m-char-succ.service'
    result = subprocess.run(['systemctl', '--user', 'show', unit,
                             '-p', 'ActiveState', '-p', 'SubState', '-p', 'Result'],
                            check=True, text=True, capture_output=True)
    properties = dict(line.split('=', 1) for line in result.stdout.splitlines())
    if properties.get('ActiveState') not in {'active', 'activating'}:
        status('production_startup_failed', service=unit, startup=properties,
               monitoring=False)
        return 1
    status('production_launched', service=unit, startup=properties,
           monitoring=False)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
