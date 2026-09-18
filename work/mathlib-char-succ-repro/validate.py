#!/usr/bin/env python3
"""Serial regression gate for a pinned Char scheduling candidate; no launch."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from resource_queue import archive_unstarted, wait_for_memory

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

ALIGN = HERE.parent / 'kernel-alignment-pass'
OLDCHAR = HERE.parent / 'mathlib-char-ordinal-repro'
RIEM = HERE.parent / 'mathlib-riemann-sharing-repro'
LIE = HERE.parent / 'mathlib-lie-trace-repro'
CONSUMER = ALIGN / 'importer.1lqiqwaI'
GATE = ALIGN / 'final-gates-char-succ-v13'

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--worker-sha', required=True)
parser.add_argument('--checker-sha', required=True)
args = parser.parse_args()
directory = HERE / 'validation-v13'
directory.mkdir()
env = {k: v for k, v in os.environ.items()
       if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
env['ROCQ_ALIGNMENT_IMPORTER'] = str(CONSUMER)
env['ROCQ_CHAR_SLICE_MEMORY_MIB'] = '8192'
if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
    env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
env['ROCQ_LEGACY_MATHLIB_GENERATION'] = str(HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal')
commands = [
    ('recursive-alias', [HERE/'run-small-native.py', HERE/'FixPriority.v', HERE/'final-alias-v13']),
    ('previous-char', [OLDCHAR/'run.py', OLDCHAR/'CharTarget.v', OLDCHAR/'succ-fix-target-v8', '--native', '--prefix', OLDCHAR/'prefix']),
    ('combined-char', [HERE/'run.py', HERE/'CharWhole.v', HERE/'final-whole-v13', '--native']),
    ('combined-independent', [HERE/'check-slice.py', HERE/'final-whole-v13']),
    ('original-order', [HERE/'run-original.py', HERE/'MathlibTo35000000.v', HERE/'final-original-v13', '--checkpoint-limit', '30000000', '--entries', '--trace-call', '105723']),
    ('original-independent', [HERE/'check-original.py', HERE/'final-original-v13']),
    ('sset', [RIEM/'run-traced.py', RIEM/'SSetTarget.v', RIEM/'sset-succ-v13', '--native', '--prefix', RIEM/'sset-prefix']),
    ('sset-independent', [RIEM/'check-target.py', RIEM/'sset-succ-v13', RIEM/'sset-prefix', '--manifest', RIEM/'sset-slice.json']),
    ('lie', [LIE/'run.py', LIE/'ProofTarget.v', LIE/'proof-succ-v13', '--native', '--prefix', LIE/'proof-prefix']),
    ('lie-independent', [RIEM/'check-target.py', LIE/'proof-succ-v13', LIE/'proof-prefix']),
    ('derivative', [RIEM/'run-traced.py', RIEM/'DerivativeTarget.v', RIEM/'derivative-succ-v13', '--native', '--prefix', RIEM/'derivative-prefix']),
    ('derivative-independent', [RIEM/'check-target.py', RIEM/'derivative-succ-v13', RIEM/'derivative-prefix', '--manifest', RIEM/'derivative-slice.json']),
    ('riemannian', [RIEM/'run-traced.py', RIEM/'RiemannianWholeFrom25M.v', RIEM/'riemannian-succ-v13', '--checkpoint-limit', '25000000']),
    ('riemannian-independent', [RIEM/'check-original-order.py', RIEM/'riemannian-succ-v13']),
    ('gates', [ALIGN/'gates.py', GATE.name]),
    ('native-independent', [ALIGN/'check-native.py', GATE]),
    ('strict-native-independent', [ALIGN/'check-native.py', GATE, 'strict-independent-check', '--strict', '--allow-uip']),
    ('strict-policy', [ALIGN/'test-strict-checker.py', 'strict-checker-char-succ-v13']),
]
# Check native/legacy policy regressions before the expensive original-order
# segment. All prior stages are rerun; old successes are historical evidence.
commands = commands[14:] + commands[12:14] + commands[:12]
inputs = {str(chunks.WORKER): args.worker_sha,
          str(chunks.KERNEL/'_build/default/checker/rocqchk.exe'): args.checker_sha}
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
budgets = {'recursive-alias': 1024, 'previous-char': 8192, 'combined-char': 8192,
           'combined-independent': 4096, 'sset-independent': 3072,
           'lie-independent': 3072, 'derivative-independent': 3072,
           'native-independent': 3072, 'strict-native-independent': 3072}
compile_directories = {
    'recursive-alias': HERE/'final-alias-v13',
    'previous-char': OLDCHAR/'succ-fix-target-v8',
    'combined-char': HERE/'final-whole-v13', 'original-order': HERE/'final-original-v13',
    'sset': RIEM/'sset-succ-v13', 'lie': LIE/'proof-succ-v13',
    'derivative': RIEM/'derivative-succ-v13', 'riemannian': RIEM/'riemannian-succ-v13'}
check_files = {
    'combined-independent': (HERE/'final-whole-v13', 'independent'),
    'original-independent': (HERE/'final-original-v13', 'independent-original-order'),
    'sset-independent': (RIEM/'sset-succ-v13', 'independent-target'),
    'lie-independent': (LIE/'proof-succ-v13', 'independent-target'),
    'derivative-independent': (RIEM/'derivative-succ-v13', 'independent-target'),
    'riemannian-independent': (RIEM/'riemannian-succ-v13', 'independent-original-order'),
    'native-independent': (GATE, 'independent-check'),
    'strict-native-independent': (GATE, 'strict-independent-check')}
results = []
refusals = []
for label, arguments in commands:
    command = [sys.executable, *map(str, arguments)]
    started = time.monotonic()
    attempt = 0
    while True:
        def waiting(**memory):
            chunks.save_json(directory/'progress.json', {
                'phase': 'waiting_for_memory', 'step': label, 'results': results,
                'refusals': refusals, **memory})
            print('WAIT', label, json.dumps(memory), flush=True)
        wait_for_memory(budgets.get(label, 16384), waiting)
        chunks.check_entries(inputs)
        print('START', label, 'attempt', attempt + 1, flush=True)
        chunks.save_json(directory/'progress.json', {
            'phase': 'running', 'step': label, 'results': results, 'refusals': refusals})
        suffix = '' if attempt == 0 else f'-retry-{attempt}'
        with (directory/(label+suffix+'.log')).open('x') as output:
            result = subprocess.run(command, cwd=ROOT, env=env,
                                    stdout=output, stderr=subprocess.STDOUT)
        chunks.check_entries(inputs)
        archived = None
        if label in compile_directories:
            stage = compile_directories[label]
            archived = archive_unstarted(result.returncode, stage/'run.log',
                stage/'result.json', fresh_directory=stage)
        elif label in check_files:
            stage, stem = check_files[label]
            archived = archive_unstarted(result.returncode, stage/(stem+'.log'), stage/(stem+'.json'))
        if archived is None:
            break
        refusals.append({'label': label, 'attempt': attempt + 1, 'archived': archived})
        print('REQUEUE pre-launch memory refusal', label, archived, flush=True)
        attempt += 1
        time.sleep(15)
    results.append({'label': label, 'exit_code': result.returncode,
                    'seconds': time.monotonic()-started, 'command': command,
                    'memory_mib': budgets.get(label, 16384)})
    chunks.save_json(directory/'progress.json', {'results': results, 'refusals': refusals,
        'phase': 'failed' if result.returncode else 'stage_passed', 'step': label})
    print('END', label, results[-1]['exit_code'], results[-1]['seconds'], flush=True)
    if result.returncode:
        raise SystemExit(result.returncode)
chunks.save_json(directory/'passed.json', {'exit_code': 0, 'inputs': inputs,
    'worker_sha256': args.worker_sha, 'checker_sha256': args.checker_sha, 'results': results,
    'refusals': refusals, 'max_memory_mib': 16384, 'reserve_mib': 3072,
    'scope': 'Proof-preserving slices and uninterrupted original-order segments; not full Mathlib acceptance'})
