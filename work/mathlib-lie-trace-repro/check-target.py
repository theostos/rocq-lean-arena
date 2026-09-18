#!/usr/bin/env python3
"""Supplementary independent target check using the already typechecked prefix.

This is deliberately NOT an independent recheck of all 2.8M dependency records.
The proof-preserving prefix was compiled separately, without abstracting proofs.
"""
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

directory = HERE / 'proof-final'
prefix = HERE / 'proof-prefix'
foundation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal/foundation'
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
inputs = {str(checker): chunks.sha(checker), str(Path(__file__)): chunks.sha(Path(__file__))}
for folder, module in ((directory, 'ProofTarget'), (prefix, 'ProofPrefix')):
    record = json.loads((folder / 'result.json').read_text())
    artifact = folder / (module + '.vo')
    assert record['exit_code'] == 0 and chunks.sha(artifact) == record['vo_sha256']
    for path in (artifact, folder / 'result.json', folder / (module + '.v')):
        inputs[str(path)] = chunks.sha(path)
for path in [foundation / 'Lean.vo', *direct.checking.STDLIB.rglob('*.vo')]:
    inputs[str(path)] = chunks.sha(path)
assert json.loads((HERE / 'slice.json').read_text())['keep_all_proofs']
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '180s',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    '-Q', str(prefix), '', '-Q', str(directory), '', '-o', '-norec', 'ProofTarget']
started = time.monotonic()
with (directory / 'independent-target.log').open('x') as output:
    result = subprocess.run(command, env=direct.environment(3072),
        stdout=output, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
chunks.save_json(directory / 'independent-target.json', {
    'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
    'command': command, 'inputs': inputs, 'admitted_dependencies': True,
    'scope': 'Independent target only; dependencies previously checked by the worker',
    'proof_preserving_prefix': str(prefix / 'result.json'),
    'strict': False, 'profile': 'unchanged importer compatibility profile'})
print(result.returncode, flush=True)
raise SystemExit(result.returncode)
