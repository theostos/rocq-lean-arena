#!/usr/bin/env python3
"""Reuse the production memory guard and proof-preserving replay harness."""
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
helper = ROOT / 'work/mathlib-riemann-sharing-repro/run-traced.py'
spec = importlib.util.spec_from_file_location('cotangent_replay', helper)
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.TARGET = 45934611
inputs = {str(p): replay.chunks.sha(p) for p in (Path(__file__), helper)}
if '--native' in sys.argv:
    manifest = HERE / 'replay.json'
    record = json.loads(manifest.read_text())
    assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
    replay.chunks.check_entries(record['inputs'])
    replay.chunks.check_entries(record['outputs'])
    inputs.update(record['outputs'])
    inputs[str(manifest)] = replay.chunks.sha(manifest)
    replay.TARGET = record['range']['start']
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
