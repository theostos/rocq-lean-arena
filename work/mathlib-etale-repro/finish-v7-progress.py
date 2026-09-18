#!/usr/bin/env python3
"""Continue unchanged v7 after a whole-library validation deadline was corrected.

Keep the failed attempt and all prior evidence immutable. Resume production
only after the remaining checks and the complete promotion guard pass.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path[:0] = [str(ROOT / 'scripts'), str(HERE.parent / 'mathlib-char-succ-repro')]
import run_chunked_import as chunks
from resource_queue import wait_for_memory
from finish import pin_inputs

STATE = HERE / 'finish-status-etale-v7-progress.json'
UNIT = 'rocq-mathlib-alignment-5m-etale-v7.service'


def status(phase, **details):
    record = {'phase': phase, 'updated_unix': time.time(), **details}
    chunks.save_json(STATE, record)
    print(json.dumps(record), flush=True)


def main():
    if STATE.exists() or (HERE / 'validation-etale-v7-progress').exists():
        raise RuntimeError('A continuation already exists; inspect it first')
    previous = HERE / 'validation-etale-v7'
    old_inputs = json.loads((previous / 'inputs.json').read_text())
    chunks.check_entries(old_inputs)
    worker = old_inputs[str(chunks.WORKER)]
    checker = old_inputs[str(chunks.KERNEL / '_build/default/checker/rocqchk.exe')]
    inputs = {str(path): digest for path, digest in pin_inputs(worker, checker).items()}
    for path, digest in old_inputs.items():
        if path in inputs and inputs[path] != digest:
            raise RuntimeError('Previously qualified input changed: ' + path)
        inputs[path] = digest
    tests = json.loads((HERE / 'deadline-tests.json').read_text())
    if tests['exit_code'] or tests['tests'] < 215 or tests['skipped'] > 2:
        raise RuntimeError('Deadline/runner qualification has not passed')
    for field in ('inputs', 'outputs'):
        chunks.check_entries(tests[field])
        for path, digest in tests[field].items():
            if path in inputs and inputs[path] != digest:
                raise RuntimeError('Conflicting test input: ' + path)
            inputs[path] = digest
    for path in (previous / 'inputs.json', previous / 'progress.json', HERE / 'deadline-tests.json'):
        inputs[str(path)] = chunks.sha(path)
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
        env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
    steps = [
        ('validation', [HERE / 'validate-v7-progress.py', '--tag', 'etale-v7',
            '--consumer', HERE.parent / 'kernel-alignment-pass/importer.eZWQ15ef',
            '--slice', HERE / 'candidate-slice-v7', '--worker-sha', worker, '--checker-sha', checker]),
        ('promotion_check', [HERE / 'resume-v7-progress.py', '--validate-only']),
        ('resume', [HERE / 'resume-v7-progress.py']),
    ]
    for step, command in steps:
        chunks.check_entries(inputs)
        if step == 'resume':
            wait_for_memory(16384, lambda **memory:
                status('waiting_for_memory', step=step, **memory))
        status('running', step=step, max_memory_mib=16384, reserve_mib=3072,
               reused_stages=6, progress=str(HERE / 'validation-etale-v7-progress/progress.json'))
        result = subprocess.run([sys.executable, *map(str, command)], cwd=ROOT, env=env)
        chunks.check_entries(inputs)
        if result.returncode:
            status('failed', step=step, exit_code=result.returncode, launch_attempted=step == 'resume')
            return result.returncode
    observed = subprocess.run(['systemctl', '--user', 'show', UNIT,
        '-p', 'ActiveState', '-p', 'SubState', '-p', 'Result'], check=True, text=True, capture_output=True)
    properties = dict(line.split('=', 1) for line in observed.stdout.splitlines())
    if properties.get('ActiveState') not in {'active', 'activating'}:
        status('production_startup_failed', service=UNIT, startup=properties, monitoring=False)
        return 1
    status('production_launched', service=UNIT, startup=properties, monitoring=False)
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        status('failed', reason=str(error), automatic_resume=False)
        raise
