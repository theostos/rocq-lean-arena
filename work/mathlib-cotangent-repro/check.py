#!/usr/bin/env python3
"""Independent slice-artifact checking at the production resource limits."""
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
record = json.loads((directory / 'result.json').read_text())
module = record['module']
assert record['exit_code'] == 0
assert module in {'CotangentStreamPrefix', 'CotangentStreamTarget', 'CotangentStreamWhole'}
manifest = HERE / 'replay.json'
slice_record = json.loads(manifest.read_text())
assert slice_record['keep_all_proofs'] and slice_record['stats']['abstracted'] == 0
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
watchdog = ROOT / 'scripts/checker_progress.py'
generation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
foundation = generation / 'foundation'
plan_path = generation / 'checkpoints/plan.json'
plan = chunks.load_plan(plan_path)
assert (plan['line_timeout'], plan['memory_mib']) == (1800, 16384)
inputs = {str(p): chunks.sha(p) for p in (
    Path(__file__), checker, watchdog, manifest, plan_path, foundation / 'Lean.vo',
    *direct.checking.STDLIB.rglob('*.vo'))}
extra = []
folders = [directory]
if args.prefix:
    prefix = args.prefix.resolve(strict=True)
    assert prefix.parent == HERE and module == 'CotangentStreamTarget'
    assert json.loads((prefix / 'result.json').read_text())['module'] == 'CotangentStreamPrefix'
    folders.append(prefix)
    extra = ['-Q', str(prefix), '']
else:
    assert module != 'CotangentStreamTarget'
for folder in folders:
    receipt = json.loads((folder / 'result.json').read_text())
    artifact = folder / (receipt['module'] + '.vo')
    assert receipt['exit_code'] == 0 and chunks.sha(artifact) == receipt['vo_sha256']
    for path in (artifact, artifact.with_suffix('.v'), folder / 'result.json',
                 folder / 'invocation.json'):
        inputs[str(path)] = chunks.sha(path)
progress_path = directory / 'independent-status.json'
command = ['bash', str(direct.checking.GUARD), sys.executable, str(watchdog),
    '--module', module, '--seconds', '1800', '--progress', str(progress_path), '--',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    *extra, '-Q', str(directory), '', '-o', '-norec', module]
chunks.check_entries(inputs)
start = time.monotonic()
with (directory / 'independent.log').open('x') as log:
    result = subprocess.run(command, env=direct.environment(16384),
                            stdout=log, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
progress = json.loads(progress_path.read_text()) if progress_path.exists() else None
if result.returncode == 0:
    assert progress and progress['phase'] == 'passed' and progress['declarations_started'] > 0
chunks.save_json(directory / 'independent.json', {
    'exit_code': result.returncode, 'wall_seconds': time.monotonic() - start,
    'command': command, 'inputs': inputs, 'progress': progress,
    'admitted_dependencies': True, 'strict': False,
    'scope': ('Target proof; reuse separately compiled proof-preserving prefix, foundation and stdlib'
              if args.prefix else 'Every declaration in this proof-preserving slice artifact; reuse foundation and stdlib'),
    'deadline_policy': '1800 seconds per declaration progress, including startup/finalization',
    'outputs': {str(progress_path): chunks.sha(progress_path)} if progress else {}})
print(result.returncode, flush=True)
raise SystemExit(result.returncode)
