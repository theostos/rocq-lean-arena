#!/usr/bin/env python3
"""Independently recheck the complete SRG slice; reuse only its foundation."""
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

directory = Path(sys.argv[1]).resolve(strict=True)
assert directory.parent == HERE
record = json.loads((directory / 'result.json').read_text())
assert record['exit_code'] == 0 and record['module'] == 'SrgWhole'
artifact = directory / 'SrgWhole.vo'
assert chunks.sha(artifact) == record['vo_sha256']
manifest = json.loads((HERE / 'slice.json').read_text())
assert manifest['keep_all_proofs'] and manifest['stats']['abstracted'] == 0
foundation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal/foundation'
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
inputs = dict(json.loads((directory / 'invocation.json').read_text())['inputs'])
for path in (Path(__file__), checker, artifact, directory / 'result.json',
             directory / 'invocation.json', foundation / 'Lean.vo',
             *direct.checking.STDLIB.rglob('*.vo')):
    inputs[str(path)] = chunks.sha(path)
chunks.check_entries(inputs)
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '1800s',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    '-Q', str(directory), '', '-o', '-norec', 'SrgWhole']
start = time.monotonic()
with (directory / 'independent.log').open('x') as log:
    result = subprocess.run(command, env=direct.environment(16384),
                            stdout=log, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
chunks.save_json(directory / 'independent.json', {
    'exit_code': result.returncode, 'wall_seconds': time.monotonic() - start,
    'command': command, 'inputs': inputs, 'admitted_dependencies': True,
    'strict': False, 'range': [1, manifest['range']['end']],
    'scope': 'All declarations/proofs of the SRG dependency slice; reuse foundation and stdlib'})
raise SystemExit(result.returncode)
