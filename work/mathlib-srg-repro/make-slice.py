#!/usr/bin/env python3
"""Extract IsSRGWith with every dependency proof retained."""
import hashlib
import importlib.util
import json
import mmap
from pathlib import Path
import runpy
import time
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = ROOT / '_deps/lean-kernel-arena/_build/tests/mathlib.ndjson'
SLICER = ROOT / 'work/mathlib-riemann-sharing-repro/slice_roots.py'
CONVERTER = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
TARGET = 'SimpleGraph.IsSRGWith'
destination = HERE / 'IsSRGWith.ndjson'
export = HERE / 'IsSRGWith.lean-export'
manifest = HERE / 'slice.json'
assert not any(p.exists() for p in (destination, export, manifest))

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

inputs = {str(p): sha(p) for p in (SOURCE, SLICER, CONVERTER, Path(__file__))}
started = time.monotonic()

class ScanMapping(mmap.mmap):
    last_advised = 0
    lines = 0
    def readline(self):
        line = super().readline()
        self.lines += 1
        if self.lines % 2000000 == 0:
            print(f'indexed {self.lines:,} source records', flush=True)
        if self.tell() - self.last_advised >= 64 * 1024 * 1024:
            end = self.tell() // mmap.PAGESIZE * mmap.PAGESIZE
            self.madvise(mmap.MADV_DONTNEED, 0, end)
            self.last_advised = end
        return line

slice_export = runpy.run_path(str(SLICER))['slice_export']
slice_export.__globals__['mmap'] = SimpleNamespace(mmap=ScanMapping, ACCESS_READ=mmap.ACCESS_READ)
stats = slice_export(SOURCE, destination, TARGET, keep=('*',), stop_after_target=True)
assert stats['abstracted'] == 0
spec = importlib.util.spec_from_file_location('converter', CONVERTER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CountingConverter(module.StreamingConverter):
    count = 0
    def emit(self, line):
        super().emit(line)
        self.count += 1

target_range = None
with destination.open() as stream, export.open('x') as output:
    converter = CountingConverter(output)
    for line in stream:
        obj = json.loads(line)
        start = converter.count + 1
        converter.convert(obj)
        if any(item['name'] == stats['root_name_ids'][TARGET]
               for item in obj.get('inductive', {}).get('types', [])):
            target_range = {'start': start, 'end': converter.count + 1}
assert target_range and target_range['end'] == converter.count + 1
assert all(sha(Path(p)) == h for p, h in inputs.items())
manifest.write_text(json.dumps({'inputs': inputs, 'keep_all_proofs': True,
    'stats': stats, 'target': TARGET, 'range': target_range,
    'stream_lines': converter.count,
    'outputs': {str(p): sha(p) for p in (destination, export)},
    'seconds': time.monotonic() - started}, indent=2) + '\n')
print(json.dumps(target_range), flush=True)
