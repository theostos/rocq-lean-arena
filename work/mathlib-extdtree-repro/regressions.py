#!/usr/bin/env python3
"""Fresh importer fixtures, compiled sequentially under one memory guard."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_from_start as checking
import run_mathlib_from_start as mathlib

TESTS = """universe_instances projection_relevance dependent_sprop_projection
sprop_record_scheme primitive_record_eliminator nullary_unit_scheme rec_single_ctor
mutual_inductives nested_containers mutual_nested_recursor nested_record_containers
nested_record_tree_cases nested_below nested_mixed_fields""".split()


def worker(directory):
    mathlib.require_guard()
    tests = directory / "tests"
    tests.mkdir()
    foundation = directory / "foundation"
    foundation.mkdir()
    shutil.copyfile(checking.IMPORTER / "src/Lean.v", foundation / "Lean.v")
    (directory / "dumps").symlink_to(checking.IMPORTER / "dumps")
    inputs = {str(path): checking.fingerprint(path)["sha256"] for path in
              [*mathlib.checker_inputs(), *(checking.IMPORTER / "tests" / (n + ".v") for n in TESTS)]}
    command = [str(checking.ROCQ), "c", "-q", "-bytecode-compiler", "no",
               "-R", str(checking.STDLIB), "Stdlib", "-I", str(checking.IMPORTER / "src"),
               "-Q", str(foundation), "LeanImport"]
    sources = [foundation / "Lean.v"]
    for name in TESTS:
        dest = tests / (name + ".v")
        shutil.copyfile(checking.IMPORTER / "tests" / dest.name, dest)
        sources.append(dest)
    for source in sources:
        print("Checking", source.name, flush=True)
        with (directory / (source.stem + ".log")).open("x") as log:
            subprocess.run(["timeout", "--kill-after=5s", "120", *command, source.name],
                           cwd=source.parent, stdout=log, stderr=subprocess.STDOUT, check=True)
        if not source.with_suffix(".vo").exists():
            raise ValueError("Missing compiled artifact: " + str(source))
    mathlib.check_inputs(inputs)
    mathlib.save_json(directory / "passed.json", {"tests": TESTS, "inputs": inputs})
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--worker", action="store_true")
    args = parser.parse_args()
    if not args.tag or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in args.tag):
        parser.error("Use a unique lowercase tag")
    directory = HERE / args.tag
    if args.worker:
        return worker(directory)
    directory.mkdir()
    with (directory / "guard.log").open("x") as log:
        code = checking.wait_for_guard(
            ["bash", str(checking.GUARD), "timeout", "--kill-after=5s", "900",
             sys.executable, str(Path(__file__).resolve()), args.tag, "--worker"],
            env=checking.environment(2048), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    mathlib.save_json(directory / "result.json", {"exit_code": code})
    print(directory, "exit:", code)
    return code


if __name__ == "__main__":
    sys.exit(main())
