#!/usr/bin/env python3
"""Independent checking of a Char replay; dependency reuse is explicit."""
import argparse
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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
parser.add_argument('--prefix', type=Path)
args = parser.parse_args()
directory = args.directory.resolve(strict=True)
assert directory.parent == HERE
foundation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal/foundation'
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
inputs = {str(p): chunks.sha(p) for p in (checker, Path(__file__), HERE / 'slice.json')}
assert json.loads((HERE / 'slice.json').read_text())['keep_all_proofs']
extra = []
for folder in ([args.prefix.resolve(strict=True)] if args.prefix else []) + [directory]:
    assert folder.parent == HERE
    record = json.loads((folder / 'result.json').read_text())
    artifact = folder / (record['module'] + '.vo')
    assert record['exit_code'] == 0 and chunks.sha(artifact) == record['vo_sha256']
    for path in (artifact, artifact.with_suffix('.v'), folder / 'result.json'):
        inputs[str(path)] = chunks.sha(path)
    extra += ['-Q', str(folder), '']
for path in [foundation / 'Lean.vo', *direct.checking.STDLIB.rglob('*.vo')]:
    inputs[str(path)] = chunks.sha(path)
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '600s',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    *extra, '-o', '-norec', record['module']]
started = time.monotonic()
with (directory / 'independent.log').open('x') as output:
    result = subprocess.run(command, env=direct.environment(4096),
        stdout=output, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
chunks.save_json(directory / 'independent.json', {
    'exit_code': result.returncode, 'seconds': time.monotonic() - started,
    'command': command, 'inputs': inputs, 'admitted_dependencies': True,
    'scope': 'Independent new-module checking, previously worker-checked dependencies reused',
    'strict': False, 'profile': 'unchanged importer compatibility profile'})
print(result.returncode, flush=True)
raise SystemExit(result.returncode)
