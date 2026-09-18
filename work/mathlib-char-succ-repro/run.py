#!/usr/bin/env python3
"""Guarded proof-preserving replay of the combined Char regression slice."""
import importlib.util
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
helper = ROOT / 'work/mathlib-riemann-sharing-repro/run-traced.py'
spec = importlib.util.spec_from_file_location('guarded_replay', helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.HERE = HERE
memory_mib = int(os.environ.get('ROCQ_CHAR_SLICE_MEMORY_MIB', '16384'))
if not 1024 <= memory_mib <= 16384 or (memory_mib != 16384 and '--native' not in sys.argv):
    raise ValueError('A smaller memory cap is only supported for native slices')
base_environment = module.direct.environment
module.direct.environment = lambda _: base_environment(memory_mib)
record = json.loads((HERE / 'slice.json').read_text())
assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
module.chunks.check_entries(record['inputs'])
module.chunks.check_entries(record['outputs'])
module.TARGET = record['ranges']['_private.Init.Data.Char.Ordinal.0.Char.succ?._proof_1']['start']
owned_inputs = {str(p): module.chunks.sha(p) for p in
                (Path(__file__), HERE / 'slice.json', helper)}
save_json = module.chunks.save_json
def save_record(path, data):
    if Path(path).name == 'invocation.json':
        data = dict(data, inputs=dict(data['inputs'], **owned_inputs), memory_mib=memory_mib)
    return save_json(path, data)
module.chunks.save_json = save_record
try:
    status = module.main()
finally:
    module.chunks.check_entries(record['inputs'])
    module.chunks.check_entries(record['outputs'])
    module.chunks.check_entries(owned_inputs)
raise SystemExit(status)
