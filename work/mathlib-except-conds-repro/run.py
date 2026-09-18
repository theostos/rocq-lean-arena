#!/usr/bin/env python3
"""Reuse the existing artifact-pinned and memory-guarded diagnostic runner."""
import importlib.util
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('replay', HERE.parent / 'mathlib-with-terminal-repro/run.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
replay.TARGET = 22058937
base_environment = replay.direct.environment
def environment(memory_mib):
    env = base_environment(memory_mib)
    if os.environ.get('ROCQ_DIAGNOSTIC_UNIT_WITNESS') == '1':
        env['ROCQ_DIAGNOSTIC_UNIT_WITNESS'] = '1'
    return env
replay.direct.environment = environment
raise SystemExit(replay.main())
