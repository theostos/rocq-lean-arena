#!/usr/bin/env python3
"""Run the two fresh imports sequentially when the shared guard is available."""
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
HARNESS = ROOT / '_worktrees/review/arena-loop-20260908/scripts/validate_importer_review.py'
COMMON = [
    '--runtime', 'experimental',
    '--runtime-prefix', str(ROOT / '_worktrees/review/rocq-experimental-runtime-20260908/_build/install/default'),
    '--stdlib', str(ROOT / '_worktrees/review/stdlib-experimental-20260908/theories'),
    '--test-timeout', '600',
]
jobs = [
    ('with', ['core', 'ablation_int64', 'ablation_finloop', 'ablation_cslib']),
    ('without', ['ablation_cslib']),
]
results = []
for variant, tests in jobs:
    attempt = 0
    announced_wait = False
    while True:
        state = subprocess.run(
            ['systemctl', '--user', 'show', '--property=LoadState', '--value', 'rocq-lean-import-heavy.scope'],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
        if state == 'loaded':
            if not announced_wait:
                print(f'{variant}: waiting for the existing guarded workload to finish', flush=True)
                announced_wait = True
            time.sleep(10)
            continue
        attempt += 1
        directory = OUT / f'{variant}-comparison-{attempt:02d}'
        if directory.exists():
            continue
        command = [sys.executable, str(HARNESS), str(ROOT / f'_worktrees/review/pr70-cslib-{variant}'), *COMMON]
        for test in tests:
            command += ['--test', f'tests/{test}.v']
        command += ['--output', str(directory)]
        print(f'{variant}: starting {directory.name}', flush=True)
        status = subprocess.run(command, cwd=ROOT).returncode
        if status == 75:
            announced_wait = False
            time.sleep(10)
            continue
        result = {'variant': variant, 'exit_code': status, 'result': str(directory / 'result.json')}
        results.append(result)
        (OUT / 'comparison-runs.json').write_text(json.dumps(results, indent=2) + '\n')
        print(json.dumps(result), flush=True)
        break
