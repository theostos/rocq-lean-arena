#!/usr/bin/env python3
"""Existing fresh regressions plus the original bitvector-adder proof."""
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]
base = runpy.run_path(str(ROOT / "work/int8-conversion-repro/validate.py"))
gate = base["gate"]
gate.REGRESSIONS["blastadd-unary-repro"] = "Fresh ProjectionSelection DiscardedParameters"

if __name__ == "__main__":
    raise SystemExit(gate.main())
