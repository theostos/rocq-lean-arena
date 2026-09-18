#!/usr/bin/env python3
"""Recheck the unchanged artifact with a progress deadline per declaration."""
import json
from pathlib import Path
import re
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
assert record['exit_code'] == 0
module = record['module']
assert module in {'EtaleWhole', 'MathlibTo35000000', 'EtaleTargetProductionBudget'}
artifact = directory / (module + '.vo')
assert chunks.sha(artifact) == record['vo_sha256']
inputs = dict(json.loads((directory / 'invocation.json').read_text())['inputs'])
generation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
foundation = generation / 'foundation'
source = artifact.with_suffix('.v')
imports = re.findall(r'Lean Import "([^"]+)" (\d+) (\d+)\.', source.read_text())
assert len(imports) == 1
export, start, end = imports[0]
extra = []
if module in {'EtaleWhole', 'EtaleTargetProductionBudget'}:
    manifest = json.loads((HERE / 'slice.json').read_text())
    assert manifest['keep_all_proofs'] and manifest['stats']['abstracted'] == 0
    assert Path(export) == HERE / 'Etale.lean-export'
    assert (int(start), int(end)) == ((1, 3140945) if module == 'EtaleWhole'
                                     else (3140944, 3140945))
    inputs[str(HERE / 'slice.json')] = chunks.sha(HERE / 'slice.json')
    scope = 'Every declaration and proof in the dependency slice; reuse foundation and stdlib'
    if module == 'EtaleTargetProductionBudget':
        prefix = HERE / 'proof-prefix'
        prefix_record = json.loads((prefix / 'result.json').read_text())
        assert prefix_record['exit_code'] == 0 and prefix_record['module'] == 'EtalePrefix'
        assert chunks.sha(prefix / 'EtalePrefix.vo') == prefix_record['vo_sha256']
        for path in (prefix / 'EtalePrefix.vo', prefix / 'result.json'):
            assert inputs[str(path)] == chunks.sha(path)
        extra = ['-Q', str(prefix), '']
        scope = 'Exact target proof; reuse the separately compiled proof-preserving prefix, foundation and stdlib'
else:
    plan_path = generation / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    assert export == plan['export'] and (int(start), int(end)) == (30000001, 31651933)
    predecessors = [c for c in plan['chunks'] if c['end'] <= 30000001]
    assert len(predecessors) == 6 and predecessors[-1]['end'] == 30000001
    for chunk in predecessors:
        assert chunks.verify_saved(plan_path.parent, chunk) is not None
        path = plan_path.parent / (chunk['module'] + '.vo')
        assert inputs.get(str(path)) == chunks.sha(path)
    extra = ['-Q', str(plan_path.parent), '']
    scope = 'Every new proof from 30M through the failing declaration; reuse sealed 0–30M ancestors'
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
for path in (checker, Path(__file__), artifact, source,
             directory / 'result.json', directory / 'invocation.json',
             foundation / 'Lean.vo', *direct.checking.STDLIB.rglob('*.vo')):
    inputs[str(path)] = chunks.sha(path)
chunks.check_entries(inputs)
watchdog = ROOT / 'scripts/checker_progress.py'
plan = chunks.load_plan(generation / 'checkpoints/plan.json')
seconds = plan['line_timeout']
assert seconds == 1800
progress_path = directory / 'independent-progress-status.json'
inputs[str(watchdog)] = chunks.sha(watchdog)
inputs[str(generation / 'checkpoints/plan.json')] = chunks.sha(generation / 'checkpoints/plan.json')
chunks.check_entries(inputs)
command = ['bash', str(direct.checking.GUARD), sys.executable, str(watchdog),
    '--module', module, '--seconds', str(seconds), '--progress', str(progress_path), '--',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    *extra, '-Q', str(directory), '', '-o', '-norec', module]
started = time.monotonic()
with (directory / 'independent-progress.log').open('x') as log:
    checked = subprocess.run(command, env=direct.environment(16384),
                             stdout=log, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
progress = json.loads(progress_path.read_text()) if progress_path.exists() else None
if checked.returncode == 0:
    assert progress and progress['phase'] == 'passed' and progress['exit_code'] == 0
    assert progress['declarations_started'] > 0
chunks.save_json(directory / 'independent-progress.json', {
    'exit_code': checked.returncode, 'wall_seconds': time.monotonic() - started,
    'command': command, 'inputs': inputs, 'admitted_dependencies': True,
    'deadline_policy': {'kind': 'declaration-progress', 'seconds': seconds,
        'startup_and_finalization_bounded': True, 'resets_on': 'target-constant-start-only'},
    'progress': progress, 'outputs': {str(progress_path): chunks.sha(progress_path)} if progress else {},
    'strict': False, 'range': [int(start), int(end)], 'scope': scope})
raise SystemExit(checked.returncode)
