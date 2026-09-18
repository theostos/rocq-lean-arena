#!/usr/bin/env python3
"""Retain the exact Penrose proof and all dependency proofs for a native replay."""
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
TARGET = '_private.ProofWidgets.Component.PenroseDiagram.0.ProofWidgets.Penrose.Diagram._proof_1'

if __name__ == '__main__':
    assert not (HERE / 'slice.json').exists()
    inputs = {str(p): sha(p) for p in (SOURCE, SLICER, HELPER, Path(__file__))}
    extract = runpy.run_path(str(SLICER))['slice_export']
    extract.__globals__['mmap'] = SimpleNamespace(mmap=helper['ScanMapping'], ACCESS_READ=mmap.ACCESS_READ)
    started = time.monotonic()
    destination = HERE / 'Penrose.ndjson'
    stats = extract(SOURCE, destination, TARGET, keep=('*',), stop_after_target=True)
    assert stats['abstracted'] == 0
    count = stats['selected']
    record = dict(inputs=inputs, outputs={str(destination): sha(destination)},
                  keep_all_proofs=True, stats=stats, target=TARGET,
                  range=dict(start=count, end=count+1), original_line=58521284,
                  seconds=time.monotonic()-started)
    assert all(sha(Path(p)) == digest for p, digest in inputs.items())
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
    for module, parent, start, end in (
            ('PenrosePrefix', '', 1, count),
            ('PenroseTarget', 'Require Import PenrosePrefix.\n', count, count+1),
            ('PenroseWhole', '', 1, count+1)):
        with (HERE / (module + '.v')).open('x') as output:
            output.write(settings + parent + f'Lean Import "{destination}" {start} {end}.\n')
    print(json.dumps(record), flush=True)
