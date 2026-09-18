#!/usr/bin/env python3
"""Independent continuation check; reuse separately checked dependency proofs.

This checks the new artifact, not all imported dependency modules again. Native
strict checking is a separate gate; the importer's existing profile is unchanged.
"""
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
parser.add_argument('prefix', type=Path)
parser.add_argument('--manifest', type=Path,
                    help='Proof-preserving slice manifest (default: slice.json beside replay)')
args = parser.parse_args()
directory = args.directory.resolve(strict=True)
prefix = args.prefix.resolve(strict=True)
assert directory.parent in (HERE, HERE.parent / 'mathlib-lie-trace-repro')
assert prefix.parent == directory.parent
foundation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal/foundation'
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
inputs = {str(checker): chunks.sha(checker), str(Path(__file__)): chunks.sha(Path(__file__))}
for folder in (prefix, directory):
    record = json.loads((folder / 'result.json').read_text())
    module = record['module']
    artifact = folder / (module + '.vo')
    assert record['exit_code'] == 0 and chunks.sha(artifact) == record['vo_sha256']
    for path in (artifact, folder / 'result.json', folder / (module + '.v')):
        inputs[str(path)] = chunks.sha(path)
for path in [foundation / 'Lean.vo', *direct.checking.STDLIB.rglob('*.vo')]:
    inputs[str(path)] = chunks.sha(path)
slice_manifest = (args.manifest or directory.parent / 'slice.json').resolve(strict=True)
assert json.loads(slice_manifest.read_text())['keep_all_proofs']
inputs[str(slice_manifest)] = chunks.sha(slice_manifest)
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '300s',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    '-Q', str(prefix), '', '-Q', str(directory), '', '-o', '-norec', module]
started = time.monotonic()
with (directory / 'independent-target.log').open('x') as output:
    result = subprocess.run(command, env=direct.environment(3072),
        stdout=output, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
chunks.save_json(directory / 'independent-target.json', {
    'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
    'command': command, 'inputs': inputs, 'admitted_dependencies': True,
    'scope': 'Independent continuation only; dependencies previously checked by the worker',
    'proof_preserving_prefix': str(prefix / 'result.json'),
    'strict': False, 'profile': 'unchanged importer compatibility profile'})
print(result.returncode, flush=True)
raise SystemExit(result.returncode)
