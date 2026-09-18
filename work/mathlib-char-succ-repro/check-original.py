#!/usr/bin/env python3
"""Check the entire new 30M–Char module independently, reusing sealed ancestors."""
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
result_path, invocation_path = directory / 'result.json', directory / 'invocation.json'
record = json.loads(result_path.read_text())
assert record['exit_code'] == 0 and record['module'] == 'MathlibTo35000000'
artifact = directory / (record['module'] + '.vo')
assert chunks.sha(artifact) == record['vo_sha256']
inputs = dict(json.loads(invocation_path.read_text())['inputs'])
generation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
plan_path = generation / 'checkpoints/plan.json'
plan = chunks.load_plan(plan_path)
predecessors = [c for c in plan['chunks'] if c['end'] <= 30000001]
assert len(predecessors) == 6 and predecessors[-1]['end'] == 30000001
for chunk in predecessors:
    path = plan_path.parent / (chunk['module'] + '.vo')
    assert inputs.get(str(path)) == chunks.sha(path)
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
for path in (checker, Path(__file__), artifact, result_path, invocation_path,
             artifact.with_suffix('.v')):
    inputs[str(path)] = chunks.sha(path)
chunks.check_entries(inputs)
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '1800s',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib',
    '-Q', str(generation / 'foundation'), 'LeanImport',
    '-Q', str(plan_path.parent), '', '-Q', str(directory), '',
    '-o', '-norec', record['module']]
started = time.monotonic()
with (directory / 'independent-original-order.log').open('x') as log:
    checked = subprocess.run(command, env=direct.environment(16384),
                             stdout=log, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
chunks.save_json(directory / 'independent-original-order.json', {
    'exit_code': checked.returncode, 'wall_seconds': time.monotonic() - started,
    'command': command, 'inputs': inputs, 'admitted_dependencies': True,
    'strict': False, 'range': [30000001, 30806241],
    'scope': 'Recheck all new proofs; reuse sealed proofs from the first 30M lines'})
raise SystemExit(checked.returncode)
