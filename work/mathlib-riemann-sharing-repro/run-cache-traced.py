#!/usr/bin/env python3
"""Replay with observational typing-cache counters (no policy override)."""
import importlib.util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('replay', HERE / 'run-traced.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
original_environment = replay.direct.environment
def environment(memory):
    env = original_environment(memory)
    env['ROCQ_DIAGNOSTIC_TYPEOPS_CACHE'] = '1'
    return env
replay.direct.environment = environment
result = replay.main()
replay.chunks.save_json(Path(sys.argv[2]) / 'diagnostic-controls.json', {
    'wrapper_sha256': replay.chunks.sha(Path(__file__)),
    'environment': {'ROCQ_DIAGNOSTIC_TYPEOPS_CACHE': '1'},
    'observational_only': True,
})
raise SystemExit(result)
