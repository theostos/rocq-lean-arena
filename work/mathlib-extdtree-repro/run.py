#!/usr/bin/env python3
"""Fresh, guarded dependency-only reproduction; never resume a library checkpoint."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_from_start as checking
import run_mathlib_from_start as mathlib


def worker(directory, minimal):
    mathlib.require_guard()
    os.environ["LEAN_IMPORT_EXCEPTION_BACKTRACE"] = "1"
    stem = "Minimal" if minimal else "ExtDTreeMap"
    export = HERE / (stem + ".lean-export")
    if not export.exists():
        exporter = (mathlib.ARENA / "_build/lean4export/leanprover_lean4_v4.29.0"
                    "/.lake/build/bin/lean4export")
        toolchain = Path("/home/theo/.elan/toolchains/leanprover--lean4---v4.29.0")
        module = "Minimal" if minimal else "Std.Data.ExtDTreeMap.Basic"
        selection = (["--", "Trigger", "DepQuotBox", "NestedFamilyBox", "quotient_projection"]
                     if minimal else ["--", "Std.ExtDTreeMap"])
        lean_env = dict(os.environ, LEAN_PATH=os.pathsep.join([str(directory), str(toolchain / "lib/lean")]))
        if minimal:
            shutil.copyfile(HERE / "Minimal.lean", directory / "Minimal.lean")
            subprocess.run(["timeout", "--kill-after=5s", "60", str(toolchain / "bin/lean"),
                            "-o", "Minimal.olean", "Minimal.lean"], cwd=directory, env=lean_env, check=True)
        ndjson = directory / (stem + ".ndjson")
        with ndjson.open("x") as output:
            subprocess.run(["timeout", "--kill-after=5s", "180", str(exporter),
                            module, *selection], env=lean_env,
                           stdout=output, check=True)
        staged = directory / (stem + ".lean-export")
        subprocess.run(["timeout", "--kill-after=5s", "180", sys.executable,
                        str(mathlib.CONVERTER), str(ndjson), str(staged)],
                       env=dict(os.environ, ROCQLKA_NDJSON_STREAM="1"), check=True)
        staged.rename(export)
    fingerprint = checking.fingerprint(export)
    mathlib.save_json(directory / "inputs.json", {
        "export": fingerprint,
        "importer": checking.fingerprint(checking.IMPORTER / "src/lean_import.cmxs"),
        "kernel": checking.fingerprint(checking.KERNEL / "_build/default/topbin/rocqworker.exe")})
    foundation = directory / "foundation"
    foundation.mkdir()
    shutil.copyfile(checking.IMPORTER / "src/Lean.v", foundation / "Lean.v")
    (directory / "Full.v").write_text(checking.full_source(export, fingerprint["lines"], 600))
    return checking.worker(directory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--minimal", action="store_true")
    args = parser.parse_args()
    if not args.tag or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in args.tag):
        parser.error("Use a unique lowercase tag")
    directory = HERE / args.tag
    if args.worker:
        return worker(directory, args.minimal)
    directory.mkdir()
    with (directory / "guard.log").open("x") as log:
        code = checking.wait_for_guard(
            ["bash", str(checking.GUARD), "timeout", "--kill-after=5s", "900",
             sys.executable, str(Path(__file__).resolve()), args.tag, "--worker",
             *(["--minimal"] if args.minimal else [])],
            env=checking.environment(2048), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    mathlib.save_json(directory / "result.json", {"exit_code": code})
    print(directory, "exit:", code)
    return code


if __name__ == "__main__":
    sys.exit(main())
