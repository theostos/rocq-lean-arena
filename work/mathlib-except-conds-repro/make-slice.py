#!/usr/bin/env python3
"""Extract the failing theorem with every dependency proof retained."""
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
source = ROOT / '_deps/lean-kernel-arena/_build/tests/mathlib.ndjson'
slicer = ROOT / 'work/mathlib-contdiff-repro/slice.py'
converter = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
ndjson = HERE / 'ExceptConds.ndjson'
export = HERE / 'ExceptConds.stream.lean-export'
manifest = HERE / 'slice.json'
assert not any(p.exists() for p in (ndjson, export, manifest))

def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

inputs = {str(p): sha(p) for p in (source, slicer, converter, Path(__file__))}
started = time.monotonic()
runpy.run_path(str(slicer))['slice_export'](source, ndjson,
    'Std.Do.ExceptConds.and_eq_left', keep=('*',), stop_after_target=True)
subprocess.run(['python3', str(converter), str(ndjson), str(export)], check=True,
    env={**os.environ, 'ROCQLKA_NDJSON_STREAM': '1'})
assert all(sha(Path(p)) == value for p, value in inputs.items())
manifest.write_text(json.dumps({'inputs': inputs, 'keep_all_proofs': True,
    'outputs': {str(p): sha(p) for p in (ndjson, export)},
    'seconds': time.monotonic() - started}, indent=2) + '\n')
print(manifest, flush=True)
