#!/usr/bin/env python3
"""Recheck the exact target artifact with the standalone kernel checker."""
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
parser.add_argument('--prefix', required=True, type=Path)
parser.add_argument('--label', default='independent')
args = parser.parse_args()
assert args.label.replace('-', '').isalnum()
directory = args.directory.resolve(strict=True)
prefix = args.prefix.resolve(strict=True)
assert directory.parent == prefix.parent == HERE
manifest = HERE / 'slice.json'
record = json.loads(manifest.read_text())
assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
watchdog = ROOT / 'scripts/checker_progress.py'
foundation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal/foundation'
inputs = {str(p): chunks.sha(p) for p in (
    Path(__file__), checker, watchdog, manifest, foundation / 'Lean.vo',
    *direct.checking.STDLIB.rglob('*.vo'))}
for folder, module in ((prefix, 'PadicPrefix'), (directory, 'PadicTarget')):
    result = json.loads((folder / 'result.json').read_text())
    artifact = folder / (module + '.vo')
    assert result['exit_code'] == 0 and result['module'] == module
    assert chunks.sha(artifact) == result['vo_sha256']
    for path in (artifact, artifact.with_suffix('.v'), folder / 'result.json',
                 folder / 'invocation.json'):
        inputs[str(path)] = chunks.sha(path)
progress_path = directory / (args.label + '-status.json')
command = ['bash', str(direct.checking.GUARD), sys.executable, str(watchdog),
    '--module', 'PadicTarget', '--seconds', '1800', '--progress', str(progress_path), '--',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    '-Q', str(prefix), '', '-Q', str(directory), '', '-o', '-norec', 'PadicTarget']
chunks.check_entries(inputs)
start = time.monotonic()
with (directory / (args.label + '.log')).open('x') as log:
    result = subprocess.run(command, env=direct.environment(16384),
                            stdout=log, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
progress = json.loads(progress_path.read_text()) if progress_path.exists() else None
if result.returncode == 0:
    assert progress and progress['phase'] == 'passed' and progress['declarations_started'] > 0
chunks.save_json(directory / (args.label + '.json'), {
    'exit_code': result.returncode, 'wall_seconds': time.monotonic() - start,
    'command': command, 'inputs': inputs, 'progress': progress,
    'admitted_dependencies': True, 'strict': False,
    'scope': 'Target proof only; reuse separately compiled proof-preserving prefix, foundation and stdlib',
    'deadline_policy': '1800 seconds per declaration progress, including startup/finalization',
    'outputs': {str(progress_path): chunks.sha(progress_path)} if progress else {}})
print(result.returncode, flush=True)
raise SystemExit(result.returncode)
