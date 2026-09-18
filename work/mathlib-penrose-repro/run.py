#!/usr/bin/env python3
"""Use the guarded serial replay harness with a proof-preserving Penrose slice."""
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
helper = ROOT / 'work/mathlib-riemann-sharing-repro/run-traced.py'
spec = importlib.util.spec_from_file_location('penrose_replay', helper)
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
record = json.loads((HERE / 'slice.json').read_text())
assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
assert '--native' in sys.argv
replay.TARGET = record['range']['start']
if '--baseline' in sys.argv:
    replay.chunks.WORKER = HERE / 'rocqworker-baseline.exe'
    sys.argv.remove('--baseline')
inputs = {str(p): replay.chunks.sha(p) for p in (Path(__file__), helper, HERE / 'slice.json')}
inputs.update(record['outputs'])
if '--legacy' in sys.argv:
    sys.argv.remove('--legacy')
    legacy_path = HERE / 'legacy.json'
    legacy = json.loads(legacy_path.read_text())
    replay.TARGET = legacy['range']['start']
    inputs.update(legacy['inputs'])
    inputs.update(legacy['outputs'])
    inputs[str(legacy_path)] = replay.chunks.sha(legacy_path)
replay.chunks.check_entries(record['inputs'])
replay.chunks.check_entries(inputs)
save_json = replay.chunks.save_json
def save_record(path, data):
    if Path(path).name == 'invocation.json':
        data = dict(data, inputs=dict(data['inputs'], **inputs))
    return save_json(path, data)
replay.chunks.save_json = save_record
try:
    status = replay.main()
finally:
    replay.chunks.check_entries(inputs)
raise SystemExit(status)
