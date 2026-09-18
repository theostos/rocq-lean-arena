#!/usr/bin/env python3
"""Record focused native cache/traversal regression checks against this build."""
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

alignment = HERE.parent / 'kernel-alignment-pass'
tests = [HERE / ('test-' + name + '.sh') for name in
         ('hashcons', 'canonical', 'conversion-hash', 'cross-dag', 'deep', 'validator')]
tests += [alignment / ('test-' + name + '.sh') for name in
          ('typeops-cache', 'syntax-substitution', 'syntax-lifting', 'witness-candidate')]
inputs = {str(p): chunks.sha(p) for p in (
    Path(__file__), chunks.WORKER, ROOT / 'work/run-memory-guarded.sh',
    *chunks.KERNEL.joinpath('kernel').glob('*.ml'),
    *chunks.KERNEL.joinpath('kernel').glob('*.mli'),
    chunks.KERNEL / 'checker/validate.ml',
    chunks.KERNEL / 'checker/mod_checking.ml',
    *HERE.glob('*.ml'), *HERE.glob('test-*.sh'),
    *alignment.glob('*.ml'), *alignment.glob('test-*.sh'))}
chunks.check_entries(inputs)
label = sys.argv[1] if len(sys.argv) > 1 else 'candidate-units'
assert label.replace('-', '').isalnum()
destination = HERE / label
destination.mkdir()
results = []
for test in tests:
    start = time.monotonic()
    log_path = destination / (test.stem + '.log')
    with log_path.open('x') as log:
        run = subprocess.run(['bash', str(test)], stdout=log, stderr=subprocess.STDOUT)
    result = dict(test=str(test), exit_code=run.returncode,
                  wall_seconds=time.monotonic()-start, log=str(log_path),
                  log_sha256=chunks.sha(log_path))
    results.append(result)
    print(json.dumps(result), flush=True)
    if run.returncode:
        break
chunks.check_entries(inputs)
chunks.save_json(destination / 'result.json', dict(
    exit_code=results[-1]['exit_code'], inputs=inputs, tests=results,
    worker_sha256=inputs[str(chunks.WORKER)],
    outputs={r['log']: r['log_sha256'] for r in results}))
raise SystemExit(results[-1]['exit_code'])
