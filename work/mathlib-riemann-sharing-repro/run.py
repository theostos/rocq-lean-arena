#!/usr/bin/env python3
"""Pinned, proof-preserving replays for the Riemannian/SSet sharing regression."""
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    'replay', HERE.parent / 'mathlib-with-terminal-repro/run.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
replay.TARGET = 26774107
raise SystemExit(replay.main())
