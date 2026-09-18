#!/usr/bin/env python3
"""Convert the sparse diagnostic slice with the existing stream converter."""
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CONVERTER = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
def sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

manifest = HERE / 'slice.json'
record = json.loads(manifest.read_text())
inputs = dict(record['inputs'], **record['outputs'])
inputs.update({str(p): sha(p) for p in (manifest, CONVERTER, Path(__file__))})
assert record['keep_all_proofs'] and record['stats']['abstracted'] == 0
assert all(sha(Path(p)) == h for p, h in inputs.items())
spec = importlib.util.spec_from_file_location('converter', CONVERTER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class CountingConverter(module.StreamingConverter):
    count = 0
    def emit(self, line):
        super().emit(line)
        self.count += 1

export = HERE / 'Cotangent.lean-export'
target_range = None
with (HERE / 'Cotangent.ndjson').open() as stream, export.open('x') as output:
    converter = CountingConverter(output)
    for line in stream:
        obj = json.loads(line)
        start = converter.count + 1
        converter.convert(obj)
        if obj.get('thm', {}).get('name') == record['stats']['root_name_ids'][record['target']]:
            target_range = dict(start=start, end=converter.count + 1)
assert target_range and target_range['end'] == converter.count + 1
assert all(sha(Path(p)) == h for p, h in inputs.items())
record.update(inputs=inputs, outputs={str(export): sha(export)}, range=target_range,
              stream_lines=converter.count)
with (HERE / 'replay.json').open('x') as f:
    json.dump(record, f, indent=2)
    f.write('\n')
settings = ('From LeanImport Require Import Lean.\n'
            'Set Kernel Conversion Dep Heuristic.\n'
            'Set Lean Error Mode "Fail".\n'
            'Unset Lean Skip Missing Quotient.\n'
            'Unset Lean Just Parsing.\n'
            'Unset Lean Lazy Instantiation.\n'
            'Set Lean Line Timeout 1800.\n')
for name, parent, start, end in (
    ('CotangentStreamPrefix', '', 1, target_range['start']),
    ('CotangentStreamTarget', 'Require Import CotangentStreamPrefix.\n',
        target_range['start'], target_range['end']),
    ('CotangentStreamWhole', '', 1, target_range['end'])):
    with (HERE / (name + '.v')).open('x') as f:
        f.write(settings + parent + f'Lean Import "{export}" {start} {end}.\n')
print(json.dumps(target_range), flush=True)
