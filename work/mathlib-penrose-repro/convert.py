#!/usr/bin/env python3
"""Convert the sparse diagnostic slice to the existing sparse-ID stream format."""
import importlib.util
import json
from pathlib import Path
import runpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sha = runpy.run_path(str(ROOT / 'work/mathlib-cotangent-repro/prepare.py'))['sha']
source = HERE / 'Penrose.ndjson'
manifest = HERE / 'slice.json'
record = json.loads(manifest.read_text())
assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
converter_path = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
spec = importlib.util.spec_from_file_location('converter', converter_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class Converter(module.StreamingConverter):
    count = 0
    def emit(self, line):
        super().emit(line)
        self.count += 1
export = HERE / 'Penrose.lean-export'
inputs = {str(p): sha(p) for p in (source,manifest,converter_path,Path(__file__))}
assert inputs[str(source)] == record['outputs'][str(source)]
with source.open() as stream, export.open('x') as output:
    converter = Converter(output)
    for line in stream:
        obj = json.loads(line)
        start = converter.count + 1
        converter.convert(obj)
        if obj.get('thm',{}).get('name') == record['stats']['root_name_ids'][record['target']]:
            target_range = dict(start=start,end=converter.count+1)
assert target_range['end'] == converter.count+1
with (HERE / 'legacy.json').open('x') as output:
    json.dump(dict(inputs=inputs,outputs={str(export):sha(export)},range=target_range),output,indent=2)
    output.write('\n')
settings = (HERE / 'PenrosePrefix.v').read_text().split('Lean Import ')[0]
for name,parent,start,end in (
        ('PenrosePrefixLegacy','',1,target_range['start']),
        ('PenroseTargetLegacy','Require Import PenrosePrefixLegacy.\n',target_range['start'],target_range['end'])):
    with (HERE / (name+'.v')).open('x') as output:
        output.write(settings + parent + f'Lean Import "{export}" {start} {end}.\n')
print(target_range)
