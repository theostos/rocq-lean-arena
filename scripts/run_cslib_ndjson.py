#!/usr/bin/env python3
"""Run the direct NDJSON cslib import from line 1 with the existing resource guard."""

import importlib.util
import os
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "_cslib_ndjson_runtime", Path(__file__).with_name("run_cslib_from_start.py"))
checking = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checking)

checking.SCRIPT = Path(__file__).resolve()
checking.IMPORTER = checking.ROOT / "_worktrees/rocq-lean-import/cslib-ndjson"
checking.EXPORT = checking.ROOT / "_deps/lean-kernel-arena/_build/tests/cslib.ndjson"
checking.RUNS = checking.ROOT / "work/cslib-ndjson"
base_environment = checking.environment


def environment(memory_mib):
    env = base_environment(memory_mib)
    env["OCAMLPATH"] += os.pathsep + str(checking.IMPORTER / "_build/findlib")
    return env


checking.environment = environment


if __name__ == "__main__":
    raise SystemExit(checking.main())
