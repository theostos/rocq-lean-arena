#!/usr/bin/env python3
"""Qualify the final worker, including the standalone load-depth repair."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

independent = HERE / 'candidate-target-6/independent-3.json'
deadline = time.monotonic() + 3600
while not independent.exists():
    if time.monotonic() >= deadline:
        raise SystemExit('Standalone check did not finish; not continuing')
    time.sleep(5)
record = json.loads(independent.read_text())
assert record['exit_code'] == 0 and record['progress']['phase'] == 'passed'
chunks.check_entries(record['inputs'])
env = dict(os.environ, ROCQ_ALIGNMENT_IMPORTER=str(
    ROOT / 'work/kernel-alignment-pass/importer.m63OyviU'))
target = HERE / 'candidate-target-7'
commands = [
    [sys.executable, str(HERE / 'run.py'), str(HERE / 'PenroseTargetLegacy.v'),
     str(target), '--prefix', str(HERE / 'baseline-prefix-legacy'), '--native', '--legacy'],
    [sys.executable, str(HERE / 'units.py'), 'candidate-units-3'],
    [sys.executable, str(HERE / 'focused.py'), str(HERE / 'candidate-focused-2')],
    [sys.executable, str(HERE.parent / 'mathlib-padic-repro/run.py'),
     str(HERE.parent / 'mathlib-padic-repro/PadicTarget.v'),
     str(HERE.parent / 'mathlib-padic-repro/penrose-regression-2'), '--prefix',
     str(HERE.parent / 'mathlib-padic-repro/baseline-prefix'), '--native']]
for command in commands:
    print('Running:', command, flush=True)
    subprocess.run(command, cwd=ROOT, env=env, check=True)

# Byte-identical artifacts need not be checked twice. Preserve the actual
# original checker command/path; do not relabel the earlier execution.
old_artifact = HERE / 'candidate-target-6/PenroseTargetLegacy.vo'
new_artifact = target / 'PenroseTargetLegacy.vo'
if chunks.sha(old_artifact) == chunks.sha(new_artifact):
    chunks.check_entries(record['inputs'])
    chunks.save_json(target / 'standalone-evidence.json', dict(
        exit_code=0, mode='identical-artifact-reuse', evidence=str(independent),
        artifact_sha256=chunks.sha(new_artifact),
        inputs={str(p): chunks.sha(p) for p in
                (Path(__file__), independent, old_artifact, new_artifact)}))
else:
    subprocess.run([sys.executable, str(HERE / 'check.py'), str(target),
                    '--prefix', str(HERE / 'baseline-prefix-legacy')],
                   cwd=ROOT, env=env, check=True)
    path = target / 'independent.json'
    chunks.save_json(target / 'standalone-evidence.json', dict(
        exit_code=0, mode='fresh-check', evidence=str(path),
        artifact_sha256=chunks.sha(new_artifact),
        inputs={str(p): chunks.sha(p) for p in (Path(__file__), path, new_artifact)}))
print('Final qualification passed; release is a separate action.', flush=True)
