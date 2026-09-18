#!/usr/bin/env python3
"""Extract the reported Char theorem, retaining every dependency proof."""
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
source = ROOT / '_deps/lean-kernel-arena/_build/tests/mathlib.ndjson'
slicer = ROOT / 'work/mathlib-riemann-sharing-repro/slice_roots.py'
converter_path = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
# The export retains numeric Name components separately; the importer's log
# concatenates them ("Ordinal0"), but the slicer renders them as ".0".
target = '_private.Init.Data.Char.Ordinal.0.Char.ofOrdinal_le_of_le._proof_1_6'
destination = HERE / 'CharOrdinal.ndjson'
export = HERE / 'CharOrdinal.lean-export'
manifest = HERE / 'slice.json'
assert not any(path.exists() for path in (destination, export, manifest))

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

inputs = {str(path): sha(path) for path in (source, slicer, converter_path, Path(__file__))}
started = time.monotonic()
class ScanMapping(mmap.mmap):
    """Release scanned PTEs, not source bytes or the OS's shared page cache."""
    last_advised = 0
    lines = 0
    def readline(self):
        line = super().readline()
        self.lines += 1
        if self.lines % 2000000 == 0:
            print(f'indexed {self.lines:,} source records', flush=True)
        position = self.tell()
        if position - self.last_advised >= 64 * 1024 * 1024:
            end = position // mmap.PAGESIZE * mmap.PAGESIZE
            self.madvise(mmap.MADV_DONTNEED, 0, end)
            self.last_advised = end
        return line

slice_export = runpy.run_path(str(slicer))['slice_export']
slice_export.__globals__['mmap'] = SimpleNamespace(mmap=ScanMapping, ACCESS_READ=mmap.ACCESS_READ)
stats = slice_export(
    source, destination, target, keep=('*',), stop_after_target=True, roots=[])
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
