#!/usr/bin/env python3
"""Finish the bounded qualification sequence after the already-running replay."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
result = HERE / 'candidate-target-6/result.json'
deadline = time.monotonic() + 3600
while not result.exists():
    if time.monotonic() >= deadline:
        raise SystemExit('Replay did not finish; no continuation authorized')
    time.sleep(5)
assert json.loads(result.read_text())['exit_code'] == 0
env = dict(os.environ, ROCQ_ALIGNMENT_IMPORTER=str(
    ROOT / 'work/kernel-alignment-pass/importer.Uysmp5IV'))
commands = [
    [sys.executable, str(HERE / 'units.py'), 'candidate-units-2'],
    [sys.executable, str(HERE / 'focused.py'), str(HERE / 'candidate-focused')],
    [sys.executable, str(HERE.parent / 'mathlib-padic-repro/run.py'),
     str(HERE.parent / 'mathlib-padic-repro/PadicTarget.v'),
     str(HERE.parent / 'mathlib-padic-repro/penrose-regression'), '--prefix',
     str(HERE.parent / 'mathlib-padic-repro/baseline-prefix'), '--native'],
    [sys.executable, str(HERE / 'check.py'), str(HERE / 'candidate-target-6'),
     '--prefix', str(HERE / 'baseline-prefix-legacy')]]
for command in commands:
    print('Running:', command, flush=True)
    subprocess.run(command, cwd=ROOT, env=env, check=True)
print('Qualification commands passed; release is a separate step.', flush=True)
