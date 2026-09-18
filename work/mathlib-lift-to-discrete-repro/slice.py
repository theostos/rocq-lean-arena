#!/usr/bin/env python3
"""Small reproducer retaining ALL dependency proof bodies (no added axioms)."""
from pathlib import Path
import runpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
slicer = runpy.run_path(str(HERE.parent / 'mathlib-contdiff-repro/slice.py'))
destination = HERE / 'LiftToDiscrete.ndjson'
if destination.exists():
    raise ValueError('Refusing to overwrite the diagnostic input')
slicer['slice_export'](
    ROOT / '_deps/lean-kernel-arena/_build/tests/mathlib.ndjson', destination,
    '_private.Mathlib.CategoryTheory.IsConnected.0.CategoryTheory.IsPreconnected.IsoConstantAux.liftToDiscrete._proof_5',
    keep=('*',), stop_after_target=True)
