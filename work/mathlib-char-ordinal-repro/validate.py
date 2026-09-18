#!/usr/bin/env python3
"""Serial, fail-closed Char fix and recent regression validation. No production launch."""
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

ALIGN = HERE.parent / 'kernel-alignment-pass'
RIEM = HERE.parent / 'mathlib-riemann-sharing-repro'
LIE = HERE.parent / 'mathlib-lie-trace-repro'
CONSUMER = ALIGN / 'importer.y7jxl7hG'
GATE = ALIGN / 'final-gates-char-eliminator'
WORKER = '80c4781a4738d0509f88630d70583415a93b8d88a1f15306561fd88c70e70940'
CHECKER = '07a7f6884cce5c79a25c2d50772e35b337038c8275b800a770b5ec601946ef6a'

def main():
    directory = HERE / 'validation'
    directory.mkdir()
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    env['ROCQ_ALIGNMENT_IMPORTER'] = str(CONSUMER)
    env['ROCQ_LEGACY_MATHLIB_GENERATION'] = str(HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal')
    commands = [
        ('char-target', [HERE/'run.py', HERE/'CharTarget.v', HERE/'final-target', '--native', '--prefix', HERE/'prefix']),
        ('char-whole', [HERE/'run.py', HERE/'CharWhole.v', HERE/'final-whole', '--native']),
        ('char-independent', [HERE/'check.py', HERE/'final-whole']),
        ('sset', [RIEM/'run-traced.py', RIEM/'SSetTarget.v', RIEM/'sset-char-final', '--native', '--prefix', RIEM/'sset-prefix']),
        ('sset-independent', [RIEM/'check-target.py', RIEM/'sset-char-final', RIEM/'sset-prefix', '--manifest', RIEM/'sset-slice.json']),
        ('lie', [LIE/'run.py', LIE/'ProofTarget.v', LIE/'proof-char-final', '--native', '--prefix', LIE/'proof-prefix']),
        ('lie-independent', [RIEM/'check-target.py', LIE/'proof-char-final', LIE/'proof-prefix']),
        ('derivative', [RIEM/'run-traced.py', RIEM/'DerivativeTarget.v', RIEM/'derivative-char-final', '--native', '--prefix', RIEM/'derivative-prefix']),
        ('derivative-independent', [RIEM/'check-target.py', RIEM/'derivative-char-final', RIEM/'derivative-prefix', '--manifest', RIEM/'derivative-slice.json']),
        ('riemannian', [RIEM/'run-traced.py', RIEM/'RiemannianWholeFrom25M.v', RIEM/'riemannian-char-final', '--checkpoint-limit', '25000000']),
        ('riemannian-independent', [RIEM/'check-original-order.py', RIEM/'riemannian-char-final']),
        ('gates', [ALIGN/'gates.py', GATE.name]),
        ('native-independent', [ALIGN/'check-native.py', GATE]),
        ('strict-native-independent', [ALIGN/'check-native.py', GATE, 'strict-independent-check', '--strict', '--allow-uip']),
        ('strict-policy', [ALIGN/'test-strict-checker.py', ALIGN/'strict-checker-char-eliminator']),
    ]
    inputs = {str(chunks.WORKER): WORKER,
              str(chunks.KERNEL/'_build/default/checker/rocqchk.exe'): CHECKER}
    for folder in (chunks.KERNEL/'kernel', chunks.KERNEL/'checker', ALIGN, HERE):
        for path in folder.iterdir():
            if path.is_file() and path.suffix in {'.ml', '.mli', '.py', '.sh', '.v'}:
                inputs[str(path)] = chunks.sha(path)
    for _, command in commands:
        for arg in command:
            if isinstance(arg, Path) and arg.is_file():
                inputs[str(arg)] = chunks.sha(arg)
    chunks.check_entries(inputs)
    chunks.save_json(directory/'inputs.json', inputs)
    results = []
    for label, arguments in commands:
        command = [sys.executable, *map(str, arguments)]
        print('START', label, flush=True)
        started = time.monotonic()
        with (directory/(label+'.log')).open('x') as output:
            result = subprocess.run(command, cwd=ROOT, env=env,
                                    stdout=output, stderr=subprocess.STDOUT)
        chunks.check_entries(inputs)
        results.append({'label': label, 'exit_code': result.returncode,
                        'seconds': time.monotonic()-started, 'command': command})
        chunks.save_json(directory/'progress.json', {'results': results})
        print('END', label, results[-1]['exit_code'], results[-1]['seconds'], flush=True)
        if result.returncode:
            return result.returncode
    chunks.save_json(directory/'passed.json', {'exit_code': 0, 'inputs': inputs,
        'worker_sha256': WORKER, 'checker_sha256': CHECKER, 'results': results,
        'scope': 'Proof-preserving Char slice and recent regressions; not a full Mathlib pass'})
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
