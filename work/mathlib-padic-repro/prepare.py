#!/usr/bin/env python3
"""Extract the exact PadicInt theorem without abstracting dependency proofs."""
import importlib.util
import json
import mmap
from pathlib import Path
import runpy
import time
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
HELPER = ROOT / 'work/mathlib-cotangent-repro/prepare.py'
helper = runpy.run_path(str(HELPER))
sha, SOURCE, SLICER = (helper[k] for k in ('sha', 'SOURCE', 'SLICER'))
CONVERTER = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
TARGET = 'PadicInt.coe_adicCompletionIntegersEquiv_apply'
assert not (HERE / 'slice.json').exists()
inputs = {str(p): sha(p) for p in (SOURCE, SLICER, CONVERTER, HELPER, Path(__file__))}
started = time.monotonic()
extract = runpy.run_path(str(SLICER))['slice_export']
extract.__globals__['mmap'] = SimpleNamespace(mmap=helper['ScanMapping'], ACCESS_READ=mmap.ACCESS_READ)
destination = HERE / 'Padic.ndjson'
assert not destination.exists()
stats = extract(SOURCE, destination, TARGET, keep=('*',), stop_after_target=True)
assert stats['abstracted'] == 0
spec = importlib.util.spec_from_file_location('converter', CONVERTER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Converter(module.StreamingConverter):
    count = 0
    def emit(self, line):
        super().emit(line)
        self.count += 1

export = HERE / 'Padic.lean-export'
target_range = None
with destination.open() as stream, export.open('x') as output:
    converter = Converter(output)
    for line in stream:
        obj = json.loads(line)
        start = converter.count + 1
        converter.convert(obj)
        if obj.get('thm', {}).get('name') == stats['root_name_ids'][TARGET]:
            target_range = dict(start=start, end=converter.count + 1)
assert target_range and target_range['end'] == converter.count + 1
assert all(sha(Path(p)) == digest for p, digest in inputs.items())
record = dict(inputs=inputs, outputs={str(p): sha(p) for p in (destination, export)},
              keep_all_proofs=True, stats=stats, target=TARGET, range=target_range,
              original_line=54302445, seconds=time.monotonic()-started)
with (HERE / 'slice.json').open('x') as output:
    json.dump(record, output, indent=2)
    output.write('\n')
settings = ('From LeanImport Require Import Lean.\n'
            'Set Kernel Conversion Dep Heuristic.\n'
            'Set Lean Error Mode "Fail".\n'
            'Unset Lean Skip Missing Quotient.\n'
            'Unset Lean Just Parsing.\n'
            'Unset Lean Lazy Instantiation.\n'
            'Set Lean Line Timeout 1800.\n')
for name, parent, start, end in (
        ('PadicPrefix', '', 1, target_range['start']),
        ('PadicTarget', 'Require Import PadicPrefix.\n', target_range['start'], target_range['end']),
        ('PadicWhole', '', 1, target_range['end'])):
    with (HERE / (name + '.v')).open('x') as output:
        output.write(settings + parent + f'Lean Import "{export}" {start} {end}.\n')
print(json.dumps(record), flush=True)
