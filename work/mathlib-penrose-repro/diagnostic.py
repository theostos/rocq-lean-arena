#!/usr/bin/env python3
import importlib.util
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
helper = ROOT / 'work/mathlib-riemann-sharing-repro/run-traced.py'
spec = importlib.util.spec_from_file_location('penrose_diag', helper)
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE, replay.TARGET, replay.TRACE = HERE, 9939, HERE / 'trace.gdb'
environment = replay.direct.environment
def traced_environment(*args, **kwargs):
    return dict(environment(*args, **kwargs), ROCQ_OPAQUE_TRACE='1', ROCQ_DIAGNOSTIC_TYPEOPS_CACHE='1')
replay.direct.environment = traced_environment
save_json = replay.chunks.save_json
def save_record(path, data):
    if Path(path).name == 'invocation.json':
        data['inputs'][str(Path(__file__))] = replay.chunks.sha(Path(__file__))
    return save_json(path, data)
replay.chunks.save_json = save_record
raise SystemExit(replay.main())
