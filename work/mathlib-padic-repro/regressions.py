#!/usr/bin/env python3
"""Run only focused kernel units and the previous two exact theorem replays."""
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

CONSUMER = HERE.parent / 'kernel-alignment-pass/importer.rEXkanSl'
SIMPLEX = HERE.parent / 'mathlib-augmented-simplex-repro'
COTANGENT = HERE.parent / 'mathlib-cotangent-repro'
PRIVATE = HERE.parent / 'kernel-alignment-pass/test-witness-candidate.sh'
GUARD = HERE.parent / 'run-memory-guarded.sh'
receipt = HERE / 'regressions.json'
assert not receipt.exists()
inputs = {str(p): chunks.sha(p) for p in (
    Path(__file__), chunks.WORKER, GUARD, PRIVATE, HERE / 'test-inversion.sh',
    HERE / 'inversion_control_test.ml', SIMPLEX / 'run.py', COTANGENT / 'run.py',
    *chunks.KERNEL.joinpath('kernel').glob('*.ml'),
    *chunks.KERNEL.joinpath('kernel').glob('*.mli'),
    *HERE.parent.joinpath('kernel-alignment-pass').glob('*.ml'),
    *chunks.KERNEL.joinpath('test-suite/unit-tests/kernel').glob('*.ml'),
    *CONSUMER.joinpath('src').glob('*.cmxs'))}
chunks.check_entries(inputs)
env = {k: v for k, v in os.environ.items()
       if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
env['ROCQ_ALIGNMENT_IMPORTER'] = str(CONSUMER)
env.update(ROCQ_MAX_RSS_KIB='1835008', ROCQ_MEMORY_MAX_KIB='2097152',
           ROCQ_MIN_AVAILABLE_KIB='3145728', ROCQ_MEMORY_SWAP_MAX_KIB='0')
steps = [
    ('inversion', ['bash', str(GUARD), 'timeout', '--kill-after=5s', '90',
                   'bash', str(HERE / 'test-inversion.sh')]),
    ('private', ['bash', str(GUARD), 'timeout', '--kill-after=5s', '300',
                 'bash', str(PRIVATE)]),
    ('simplex', [sys.executable, str(SIMPLEX / 'run.py'), '--native', '--prefix',
                 str(SIMPLEX / 'baseline-prefix'), str(SIMPLEX / 'SimplexTarget.v'),
                 str(SIMPLEX / 'padic-regression')]),
    ('cotangent', [sys.executable, str(COTANGENT / 'run.py'), '--native', '--prefix',
                   str(COTANGENT / 'baseline-stream-prefix'),
                   str(COTANGENT / 'CotangentStreamTarget.v'),
                   str(COTANGENT / 'padic-regression')]),
]
results = []
for name, command in steps:
    log = HERE / ('regression-' + name + '.log')
    started = time.monotonic()
    with log.open('x') as output:
        result = subprocess.run(command, cwd=ROOT, env=env,
                                stdout=output, stderr=subprocess.STDOUT)
    results.append(dict(name=name, command=command, exit_code=result.returncode,
                        wall_seconds=time.monotonic()-started,
                        log=str(log), log_sha256=chunks.sha(log)))
    print(json.dumps(results[-1]), flush=True)
    if result.returncode:
        break
chunks.check_entries(inputs)
code = results[-1]['exit_code']
chunks.save_json(receipt, dict(exit_code=code, inputs=inputs, steps=results,
    outputs={r['log']: r['log_sha256'] for r in results},
    worker_sha256=inputs[str(chunks.WORKER)]))
raise SystemExit(code)
