#!/usr/bin/env python3
"""Diagnostic only: test the existing projection-congruence-first strategy."""
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
helper = ROOT / 'work/mathlib-riemann-sharing-repro/run-traced.py'
spec = importlib.util.spec_from_file_location('guarded_replay', helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.HERE = HERE
module.TARGET = 31651932
trace_head = None
if '--trace-head' in sys.argv:
    index = sys.argv.index('--trace-head')
    trace_head = sys.argv[index + 1]
    del sys.argv[index:index + 2]
base_environment = module.direct.environment
def environment(memory):
    env = base_environment(memory)
    env['ROCQ_DIAGNOSTIC_TYPEOPS_CACHE'] = '1'
    env['ROCQ_DIAGNOSTIC_PROJECTION_FIRST'] = '1'
    if trace_head is not None:
        env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_HEAD'] = trace_head
    return env
module.direct.environment = environment
inputs = {str(p): module.chunks.sha(p) for p in (Path(__file__), helper)}
if '--native' in sys.argv:
    manifest = HERE / 'slice.json'
    record = json.loads(manifest.read_text())
    assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
    module.chunks.check_entries(record['inputs'])
    module.chunks.check_entries(record['outputs'])
    inputs.update(record['outputs'])
    inputs[str(manifest)] = module.chunks.sha(manifest)
    module.TARGET = record['range']['start']
save_json = module.chunks.save_json
def save_record(path, data):
    if Path(path).name == 'invocation.json':
        data = dict(data, inputs=dict(data['inputs'], **inputs),
                    diagnostic_trace_head=trace_head,
                    diagnostic_projection_first=True)
    return save_json(path, data)
module.chunks.save_json = save_record
try:
    status = module.main()
finally:
    module.chunks.check_entries(inputs)
raise SystemExit(status)
