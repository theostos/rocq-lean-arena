#!/usr/bin/env python3
"""Fast diagnostic only: dependency theorem bodies become assumptions.

This export is never evidence of proof verification; use LieTrace for that.
"""
import os
from pathlib import Path
import runpy
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
runpy.run_path(str(ROOT / 'work/mathlib-contdiff-repro/slice.py'))['slice_export'](
    HERE / 'LieTrace.ndjson', HERE / 'Diagnostic.ndjson',
    'LieModule.lowerCentralSeries_one_inf_center_le_ker_traceForm',
    stop_after_target=True)
subprocess.run(['python3', str(ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'),
    str(HERE / 'Diagnostic.ndjson'), str(HERE / 'Diagnostic.stream.lean-export')],
    check=True, env={**os.environ, 'ROCQLKA_NDJSON_STREAM': '1'})
