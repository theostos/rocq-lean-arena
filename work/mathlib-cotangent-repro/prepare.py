#!/usr/bin/env python3
"""Extract the exact cotangent proof and all its dependency proofs."""
import hashlib
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
TARGET = ('_private.Mathlib.RingTheory.Extension.Cotangent.Basis.0.Algebra.'
          'Generators.PresentationOfFreeCotangent.Aux.cotangentEquivProd_symm_apply')

def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

class ScanMapping(mmap.mmap):
    last_advised = 0
    lines = 0
    def readline(self):
        line = super().readline()
        self.lines += 1
        if self.lines % 2000000 == 0:
            print(f'indexed {self.lines:,} records', flush=True)
        if self.tell() - self.last_advised >= 64 * 1024 * 1024:
            end = self.tell() // mmap.PAGESIZE * mmap.PAGESIZE
            self.madvise(mmap.MADV_DONTNEED, 0, end)
            self.last_advised = end
        return line

if __name__ == '__main__':
    destination = HERE / 'Cotangent.ndjson'
    manifest = HERE / 'slice.json'
    assert not destination.exists() and not manifest.exists()
    inputs = {str(p): sha(p) for p in (SOURCE, SLICER, Path(__file__))}
    started = time.monotonic()
    extract = runpy.run_path(str(SLICER))['slice_export']
    extract.__globals__['mmap'] = SimpleNamespace(mmap=ScanMapping, ACCESS_READ=mmap.ACCESS_READ)
    stats = extract(SOURCE, destination, TARGET, keep=('*',), stop_after_target=True)
    assert stats['abstracted'] == 0
    count = stats['selected']
    last = json.loads(destination.read_bytes().splitlines()[-1])
    assert last['thm']['name'] == stats['root_name_ids'][TARGET]
    record = dict(inputs=inputs, outputs={str(destination): sha(destination)},
                  keep_all_proofs=True, stats=stats, target=TARGET,
                  range=dict(start=count, end=count+1),
                  seconds=time.monotonic()-started)
    manifest.write_text(json.dumps(record, indent=2) + '\n')
    settings = ('From LeanImport Require Import Lean.\n'
                'Set Kernel Conversion Dep Heuristic.\n'
                'Set Lean Error Mode "Fail".\n'
                'Unset Lean Skip Missing Quotient.\n'
                'Unset Lean Just Parsing.\n'
                'Unset Lean Lazy Instantiation.\n'
                'Set Lean Line Timeout 1800.\n')
    for module, parent, start, end in (
            ('CotangentPrefix', '', 1, count),
            ('CotangentTarget', 'Require Import CotangentPrefix.\n', count, count+1),
            ('CotangentWhole', '', 1, count+1)):
        (HERE / (module + '.v')).write_text(settings + parent +
            f'Lean Import "{destination}" {start} {end}.\n')
    print(json.dumps(record), flush=True)
