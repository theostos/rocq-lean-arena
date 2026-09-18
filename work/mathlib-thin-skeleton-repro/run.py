#!/usr/bin/env python3
"""Reuse the pinned diagnostic runner with this generation and target."""
import importlib.util
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('replay', HERE.parent / 'mathlib-with-terminal-repro/run.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
replay.TARGET = 12973729
base_environment = replay.direct.environment
def environment(memory_mib):
    env = base_environment(memory_mib)
    if os.environ.get('ROCQ_DIAGNOSTIC_UNIT_WITNESS') == '1':
        env['ROCQ_DIAGNOSTIC_UNIT_WITNESS'] = '1'
    return env
replay.direct.environment = environment
inputs = {str(Path(__file__)): replay.chunks.sha(Path(__file__))}
result = replay.main()
replay.chunks.check_entries(inputs)
raise SystemExit(result)
