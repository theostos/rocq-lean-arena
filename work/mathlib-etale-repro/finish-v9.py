#!/usr/bin/env python3
"""Run the complete pinned validation, then resume only after every check passes.

This supervisor does not monitor the production loop. Resource admission and
per-declaration timeouts remain enforced by the existing runners.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'mathlib-char-succ-repro'))
from resource_queue import archive_unstarted, wait_for_memory
STATE = HERE / 'finish-status-etale-v9.json'


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
    parser.add_argument('--consumer', required=True, type=Path)
    args = parser.parse_args()
    consumer = args.consumer.resolve(strict=True)
    if consumer.parent != HERE.parent / 'kernel-alignment-pass' or not consumer.name.startswith('importer.'):
        raise ValueError('Expected a fresh candidate importer')
    if (STATE.exists() or (HERE / 'validation-etale-v9').exists()
            or (HERE / 'candidate-slice-v9').exists()):
        raise RuntimeError('A validation attempt already exists; inspect it first')
    target = HERE / 'candidate-target-v9-production-budget'
    checked = json.loads((target / 'result.json').read_text())
    independent = json.loads((target / 'independent.json').read_text())
    if (checked['exit_code'] != 0 or checked['worker_sha256'] != args.worker_sha
            or independent['exit_code'] != 0):
        raise RuntimeError('The exact target must pass compilation and independent checking first')
    inputs = pin_inputs(args.worker_sha, args.checker_sha)
    for filename in ('result.json', 'invocation.json', 'independent.json',
                     'EtaleTargetProductionBudget.vo'):
        path = target / filename
        inputs[path] = digest(path)
    if digest(target / 'EtaleTargetProductionBudget.vo') != checked['vo_sha256']:
        raise RuntimeError('The tested target artifact changed')
    for path, expected in independent['inputs'].items():
        if digest(Path(path)) != expected:
            raise RuntimeError('An independent-check input changed: ' + path)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    env['ROCQ_ALIGNMENT_IMPORTER'] = str(consumer)
    if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
        env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
    # Each validation stage now waits for its own budget. Small checks can
    # proceed while the large replay waits for 16 GiB plus the 3 GiB reserve.
    if any(digest(path) != expected for path, expected in inputs.items()):
        status('failed', step='admission', reason='Candidate inputs changed while queued')
        return 1
    status('validating', worker_sha256=args.worker_sha,
           checker_sha256=args.checker_sha, progress=str(HERE / 'validation-etale-v9/progress.json'),
           max_memory_mib=16384, reserve_mib=3072)
    steps = [
        ('full_slice', [HERE / 'run.py', HERE / 'EtaleWhole.v',
                        HERE / 'candidate-slice-v9', '--native']),
        ('validation', [HERE / 'validate.py', '--tag', 'etale-v9',
                        '--consumer', consumer,
                        '--slice', HERE / 'candidate-slice-v9',
                        '--worker-sha', args.worker_sha, '--checker-sha', args.checker_sha]),
        ('promotion_check', [HERE / 'resume-v9.py', '--validate-only']),
        ('resume', [HERE / 'resume-v9.py']),
    ]
    for phase, command in steps:
        if any(digest(path) != expected for path, expected in inputs.items()):
            status('failed', step=phase, reason='Pinned candidate inputs changed')
            return 1
        if phase in {'full_slice', 'resume'}:
            wait_for_memory(16384, lambda **memory:
                status('waiting_for_memory', step=phase, **memory))
        status('running', step=phase, max_memory_mib=16384, reserve_mib=3072)
        while True:
            result = subprocess.run([sys.executable, *map(str, command)], cwd=ROOT, env=env)
            slice_dir = HERE / 'candidate-slice-v9'
            archived = (archive_unstarted(result.returncode, slice_dir / 'run.log',
                        slice_dir / 'result.json', fresh_directory=slice_dir)
                        if phase == 'full_slice' else None)
            if archived is None:
                break
            wait_for_memory(16384, lambda **memory:
                status('waiting_for_memory', step=phase, archived=archived, **memory))
        if result.returncode:
            status('failed', step=phase, exit_code=result.returncode,
                   launch_attempted=phase == 'resume')
            return result.returncode
    # One startup observation, not recurring production monitoring.
    unit = 'rocq-mathlib-alignment-5m-etale-v9.service'
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
    try:
        raise SystemExit(main())
    except Exception as error:
        status('failed', reason=str(error), automatic_resume=False)
        raise

