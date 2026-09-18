#!/usr/bin/env python3
"""Guarded original-order Char replay, with declaration diagnostics at the crash."""
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
helper = ROOT / 'work/mathlib-riemann-sharing-repro/run-traced.py'
spec = importlib.util.spec_from_file_location('guarded_original', helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.HERE = HERE
module.TARGET = 30778865
owned_inputs = {str(p): module.chunks.sha(p) for p in (Path(__file__), helper)}
# Target-only experiments may reuse the already verified diagnostic ancestor.
# Recheck every unique ancestor input, including all six checkpoint artifacts,
# instead of rereading the same source through each overlapping producer seal.
# This is not used by production or by the uninterrupted original-order replay.
if '--native' in sys.argv:
    prefix = HERE / 'original-prefix'
    assert '--prefix' in sys.argv
    assert Path(sys.argv[sys.argv.index('--prefix') + 1]).resolve() == prefix
    source = Path(sys.argv[1]).resolve(strict=True)
    assert source.parent == HERE and 'Require Import CharOriginalPrefix.' in source.read_text()
    result_path, invocation_path = prefix / 'result.json', prefix / 'invocation.json'
    result = json.loads(result_path.read_text())
    assert result['exit_code'] == 0 and result['module'] == 'CharOriginalPrefix'
    ancestor_inputs = dict(json.loads(invocation_path.read_text())['inputs'])
    producer = ancestor_inputs.pop(str(module.chunks.WORKER))
    assert producer == result['worker_sha256']
    ancestor_inputs[str(HERE / 'baseline-worker.exe')] = producer
    for path in (result_path, invocation_path):
        ancestor_inputs[str(path)] = module.chunks.sha(path)
    ancestor_inputs[str(prefix / 'CharOriginalPrefix.vo')] = result['vo_sha256']
    module.chunks.check_entries(ancestor_inputs)
    owned_inputs.update(ancestor_inputs)
save_json = module.chunks.save_json
def save_record(path, data):
    if Path(path).name == 'invocation.json':
        data = dict(data, inputs=dict(data['inputs'], **owned_inputs))
    return save_json(path, data)
module.chunks.save_json = save_record
try:
    status = module.main()
finally:
    module.chunks.check_entries(owned_inputs)
raise SystemExit(status)
