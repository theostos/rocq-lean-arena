#!/usr/bin/env python3
"""Run the requested eight-worker experiment, then the one-worker comparison."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
IMPORTER = ROOT / '_worktrees/rocq-lean-import/distributed-import'
ROCQ = ROOT / '_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq'
STDLIB = ROOT / '_worktrees/rocq/stdlib-int32-repro/theories'
INPUT = HERE / 'mathlib-first1000.ndjson'


def fingerprint(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


paths = [ROCQ, IMPORTER / 'src/lean_import.cmxs', IMPORTER / 'src/Lean.v',
         IMPORTER / 'tools/parallel_import.py', *sorted((IMPORTER / 'tools/distributed').glob('*.py'))]
identities = {str(p): fingerprint(p) for p in paths}
commands = []
for workers in (8, 1):
    command = [sys.executable, str(IMPORTER / 'tools/parallel_import.py'), str(INPUT),
               '--output', str(HERE / f'workers-{workers}'), '--rocq', str(ROCQ), '--stdlib', str(STDLIB),
               '--workers', str(workers), '--batch-entries', '128', '--memory-mib', '16384',
               '--worker-memory-mib', '1536', '--coordinator-memory-mib', '1024',
               '--timeout', '21600', '--line-timeout', '600', '--max-attempts', '1024']
    commands.append({'workers': workers, 'command': command})
(HERE / 'commands.json').write_text(json.dumps({'toolchain': identities, 'commands': commands}, indent=2) + '\n')
results = []
for item in commands:
    if any(fingerprint(Path(p)) != digest for p, digest in identities.items()):
        raise RuntimeError('implementation or toolchain changed between comparisons')
    workers = item['workers']
    print(f'Starting {workers} workers at {datetime.now(timezone.utc).isoformat()}', flush=True)
    started = time.monotonic()
    log_path = HERE / f'workers-{workers}.log'
    with log_path.open('xb') as log:
        code = subprocess.run(item['command'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode
    elapsed = time.monotonic() - started
    receipt_path = HERE / f'workers-{workers}/result.json'
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else None
    log_text = log_path.read_text()
    peak = re.search(r'cgroup peak=(\d+) KiB', log_text)
    result = {'workers': workers, 'exit_code': code, 'launcher_wall_seconds': elapsed,
              'peak_cgroup_kib': int(peak[1]) if peak else None, 'receipt': receipt}
    results.append(result)
    (HERE / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'receipt'}), flush=True)
    print('Accepted:', bool(receipt and receipt.get('accepted')), flush=True)
print('Both experiments finished:', HERE / 'results.json', flush=True)
