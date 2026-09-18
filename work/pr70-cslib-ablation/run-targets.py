#!/usr/bin/env python3
"""Follow the full-export comparison with focused original CSLib declarations."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]


def wait_slot():
    while subprocess.run(
        ['systemctl', '--user', 'show', '--property=LoadState', '--value', 'rocq-lean-import-heavy.scope'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip() == 'loaded':
        time.sleep(10)


while not (OUT / 'comparison-runs.json').exists() or len(json.loads((OUT / 'comparison-runs.json').read_text())) < 2:
    time.sleep(10)
print('Full-export comparison finished; waiting to export focused declarations.', flush=True)
environment = {**os.environ, 'ROCQ_MAX_RSS_KIB': '4194304', 'ROCQ_MEMORY_MAX_KIB': '4194304',
               'ROCQ_MEMORY_HIGH_KIB': '4194304', 'ROCQ_MIN_AVAILABLE_KIB': '6291456',
               'ROCQ_MEMORY_SWAP_MAX_KIB': '0'}
attempt = 0
while True:
    wait_slot()
    attempt += 1
    if (OUT / f'target-export-{attempt:02d}.log').exists():
        continue
    with (OUT / f'target-export-{attempt:02d}.log').open('w') as log:
        status = subprocess.run(['bash', str(ROOT / 'checkers/rocq-lean-import/scripts/run-memory-guarded.sh'),
                                 sys.executable, str(OUT / 'export-targets.py')],
                                cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT).returncode
    if status == 75:
        time.sleep(10)
        continue
    if status:
        print(f'Export failed with status {status}', flush=True)
        sys.exit(status)
    break
print('Original Lean 4.27 targets exported.', flush=True)
results = []
for variant in ['without', 'with']:
    attempt = 0
    while True:
        wait_slot()
        attempt += 1
        output = OUT / f'{variant}-targets-{attempt:02d}'
        if output.exists():
            continue
        command = [sys.executable,
                   str(ROOT / '_worktrees/review/arena-loop-20260908/scripts/validate_importer_review.py'),
                   str(ROOT / f'_worktrees/review/pr70-cslib-{variant}'),
                   '--runtime', 'experimental',
                   '--runtime-prefix', str(ROOT / '_worktrees/review/rocq-experimental-runtime-20260908/_build/install/default'),
                   '--stdlib', str(ROOT / '_worktrees/review/stdlib-experimental-20260908/theories'),
                   '--test', 'tests/ablation_freem427.v',
                   '--test', 'tests/ablation_discrtree427.v',
                   '--test', 'tests/mutual_instances.v',
                   '--test', 'tests/nested_containers.v',
                   '--test', 'tests/mutual_nested_recursor.v',
                   '--output', str(output)]
        print(f'{variant}: starting focused targets', flush=True)
        status = subprocess.run(command, cwd=ROOT).returncode
        if status == 75:
            time.sleep(10)
            continue
        result = {'variant': variant, 'exit_code': status, 'result': str(output / 'result.json')}
        results.append(result)
        (OUT / 'target-runs.json').write_text(json.dumps(results, indent=2) + '\n')
        print(json.dumps(result), flush=True)
        break
