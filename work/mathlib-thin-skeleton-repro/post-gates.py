#!/usr/bin/env python3
"""Finish independent validation, then request the already-authorized resume."""
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

gate = HERE.parent / 'kernel-alignment-pass/final-gates-21/passed.json'
record = json.loads(gate.read_text())
assert record['worker_sha256'] == chunks.sha(chunks.WORKER)
inputs = {str(gate): chunks.sha(gate), str(Path(__file__)): chunks.sha(Path(__file__))}
env = dict(os.environ,
    ROCQ_ALIGNMENT_IMPORTER=str(HERE.parent / 'kernel-alignment-pass/importer.lFy9zJVL'))
commands = [
    [sys.executable, str(HERE / 'check-slice.py'), str(HERE / 'slice-final'), '--compatibility'],
    [sys.executable, 'work/kernel-alignment-pass/check-native.py', 'final-gates-21'],
    [sys.executable, 'work/kernel-alignment-pass/check-native.py', 'final-gates-21',
     'strict-independent-check', '--strict', '--allow-uip'],
    [sys.executable, 'work/kernel-alignment-pass/test-strict-checker.py', 'strict-checker-6'],
    [sys.executable, str(HERE / 'resume.py')],
]
for index, command in enumerate(commands):
    chunks.check_entries(inputs)
    chunks.save_json(HERE / 'post-gates-status.json', {'step': index + 1, 'command': command,
        'phase': 'running', 'total': len(commands)})
    print('START', index + 1, ' '.join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, env=env)
    if result.returncode:
        chunks.save_json(HERE / 'post-gates-status.json', {'step': index + 1,
            'phase': 'failed', 'exit_code': result.returncode, 'command': command})
        raise SystemExit(result.returncode)
chunks.check_entries(inputs)
chunks.save_json(HERE / 'post-gates-status.json', {'phase': 'complete', 'exit_code': 0,
    'inputs': inputs, 'commands': commands, 'full_mathlib_completed': False})
