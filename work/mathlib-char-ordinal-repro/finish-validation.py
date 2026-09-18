#!/usr/bin/env python3
"""Retry only a malformed final harness invocation after the batch finishes.

test-strict-checker.py takes a directory NAME, not an absolute path. Preserve
the initial orchestration failure, verify every frozen input, and rerun that
last policy stage with the correct argument. Never rerun or mask test failures.
"""
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


def main():
    directory = HERE / 'validation'
    passed = directory / 'passed.json'
    if passed.exists():
        raise RuntimeError('Validation already finalized')
    progress = json.loads((directory / 'progress.json').read_text())
    results = progress['results']
    if not (len(results) == 15 and all(r['exit_code'] == 0 for r in results[:14])
            and results[-1]['label'] == 'strict-policy' and results[-1]['exit_code'] == 1):
        raise RuntimeError('Expected only the known final argument-validation failure')
    error = (directory / 'strict-policy.log').read_text()
    if 'ValueError: Expected a fresh diagnostic directory name' not in error:
        raise RuntimeError('Unexpected policy-stage failure; inspect it instead of retrying')
    inputs = json.loads((directory / 'inputs.json').read_text())
    chunks.check_entries(inputs)
    target = HERE.parent / 'kernel-alignment-pass/strict-checker-char-eliminator'
    if target.exists():
        raise RuntimeError('The corrected policy output directory already exists')
    command = [sys.executable, str(target.parent / 'test-strict-checker.py'), target.name]
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    env['ROCQ_ALIGNMENT_IMPORTER'] = str(target.parent / 'importer.y7jxl7hG')
    started = time.monotonic()
    with (directory / 'strict-policy-retry.log').open('x') as output:
        result = subprocess.run(command, cwd=ROOT, env=env,
                                stdout=output, stderr=subprocess.STDOUT)
    chunks.check_entries(inputs)
    retry = {'label': 'strict-policy', 'command': command, 'exit_code': result.returncode,
             'seconds': time.monotonic() - started}
    chunks.save_json(directory / 'strict-policy-retry.json', retry)
    if result.returncode:
        return result.returncode
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    chunks.save_json(passed, {
        'exit_code': 0, 'inputs': inputs, 'worker_sha256': inputs[str(chunks.WORKER)],
        'checker_sha256': inputs[str(checker)], 'results': results[:14] + [retry],
        'orchestration_attempts': [results[-1]],
        'orchestration_correction': 'Final policy harness takes a directory name, not a path',
        'completion_inputs': {str(Path(__file__)): chunks.sha(Path(__file__)),
                              **{str(directory / name): chunks.sha(directory / name)
                                 for name in ('progress.json', 'strict-policy.log',
                                              'strict-policy-retry.log', 'strict-policy-retry.json')}},
        'scope': 'Proof-preserving Char slice and recent regressions; not a full Mathlib pass'})
    print('All 15 validation stages passed; original harness argument error retained.', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
