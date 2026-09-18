#!/usr/bin/env python3
"""Reuse the guarded replay harness for hasFTaylorSeriesUpToOn_pi from 19M."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('basic_open_replay', HERE.parent / 'mathlib-basic-open-repro/run.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.TARGET = 19571205
replay.CHECKPOINT_END = 19000001

if __name__ == '__main__':
    raise SystemExit(replay.main())
