#!/usr/bin/env python3
"""All-proof derivative-congruence isolation from the combined regression."""
import hashlib
import importlib.util
import json
from pathlib import Path
import runpy
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
source = HERE / 'Combined.ndjson'
slicer = HERE / 'slice_roots.py'
converter_path = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
roots = []
target = 'iteratedFDerivWithin_eventually_congr_set\''
destination = HERE / 'Derivative.ndjson'
export = HERE / 'Derivative.lean-export'
manifest = HERE / 'derivative-slice.json'
assert not any(path.exists() for path in (destination, export, manifest))

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

inputs = {str(path): sha(path) for path in (source, slicer, converter_path, Path(__file__))}
started = time.monotonic()
stats = runpy.run_path(str(slicer))['slice_export'](
    source, destination, target, keep=('*',), stop_after_target=True, roots=roots)
assert stats['abstracted'] == 0
spec = importlib.util.spec_from_file_location('converter', converter_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CountingConverter(module.StreamingConverter):
    count = 0
    def emit(self, line):
        super().emit(line)
        self.count += 1

ranges = {}
ids = stats['root_name_ids']
with destination.open() as stream, export.open('x') as output:
    converter = CountingConverter(output)
    for line in stream:
        obj = json.loads(line)
        if 'inductive' in obj:
            names = [item['name'] for key in ('types', 'ctors', 'recs')
                     for item in obj['inductive'][key]]
        elif set(obj) & {'def', 'thm', 'axiom', 'quot'}:
            names = [next(iter(obj.values()))['name']]
        else:
            names = []
        start = converter.count + 1
        converter.convert(obj)
        for root, name in ids.items():
            if name in names:
                ranges[root] = {'start': start, 'end': converter.count + 1}
assert set(ranges) == set(ids)
assert all(sha(Path(path)) == digest for path, digest in inputs.items())
manifest.write_text(json.dumps({'inputs': inputs, 'keep_all_proofs': True,
    'stats': stats, 'ranges': ranges, 'stream_lines': converter.count,
    'outputs': {str(path): sha(path) for path in (destination, export)},
    'seconds': time.monotonic() - started}, indent=2) + '\n')
print(manifest, flush=True)
