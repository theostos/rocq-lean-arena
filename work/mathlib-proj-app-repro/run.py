#!/usr/bin/env python3
"""Guarded diagnostics for the projective-spectrum conversion stall."""
from pathlib import Path
import importlib.util

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    'punit_replay_harness', HERE.parent / 'mathlib-punit-ext-repro/run.py')
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)
harness.HERE = HERE
harness.TARGET = 13626505

if __name__ == '__main__':
    raise SystemExit(harness.main())
