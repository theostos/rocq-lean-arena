#!/usr/bin/env python3
import argparse
import hashlib
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


def worker(directory, line_timeout, trace, lazy_dependencies, abstract_proofs, sliced, keep):
    mathlib.require_guard()
    os.environ["LEAN_IMPORT_EXCEPTION_BACKTRACE"] = "1"
    export = HERE / "Target.lean-export"
    if not export.exists():
        exporter = mathlib.ARENA / "_build/lean4export/leanprover_lean4_v4.29.0/.lake/build/bin/lean4export"
        toolchain = Path("/home/theo/.elan/toolchains/leanprover--lean4---v4.29.0")
        source = mathlib.ARENA / "_build/tests/work/mathlib/src"
        paths = [source / ".lake/build/lib/lean", toolchain / "lib/lean"]
        paths.extend(sorted((source / ".lake/packages").glob("*/.lake/build/lib/lean")))
        ndjson = directory / "Target.ndjson"
        with ndjson.open("x") as output:
            subprocess.run(["timeout", "--kill-after=5s", "180", str(exporter),
                            "Mathlib.Analysis.Complex.RealDeriv", "--", "ContDiffAt.real_of_complex"],
                           env=dict(os.environ, LEAN_PATH=os.pathsep.join(map(str, paths))),
                           stdout=output, check=True)
        staged = directory / "Target.lean-export"
        subprocess.run(["timeout", "--kill-after=5s", "180", sys.executable,
                        str(mathlib.CONVERTER), str(ndjson), str(staged)],
                       env=dict(os.environ, ROCQLKA_NDJSON_STREAM="1"), check=True)
        staged.rename(export)
    if abstract_proofs:
        export = HERE / "Abstract.lean-export"
        if not export.exists():
            staged = directory / "Abstract.lean-export"
            subprocess.run([sys.executable, str(HERE / "abstract_proofs.py"),
                            str(HERE / "baseline/Target.ndjson"), str(staged),
                            "ContDiffAt.real_of_complex"], check=True)
            staged.rename(export)
    if sliced:
        version = hashlib.sha256((checking.fingerprint(HERE / "slice.py")["sha256"]
                                  + repr(sorted(keep))).encode()).hexdigest()[:12]
        export = HERE / ("Sliced-" + version + ".lean-export")
        if not export.exists():
            ndjson = directory / "Sliced.ndjson"
            subprocess.run([sys.executable, str(HERE / "slice.py"),
                            str(HERE / "baseline/Target.ndjson"), str(ndjson),
                            "ContDiffAt.real_of_complex", *keep], check=True)
            staged = directory / "Sliced.lean-export"
            subprocess.run([sys.executable, str(mathlib.CONVERTER), str(ndjson), str(staged)],
                           env=dict(os.environ, ROCQLKA_NDJSON_STREAM="1"), check=True)
            staged.rename(export)
    fingerprint = checking.fingerprint(export)
    if trace:
        os.environ["LEAN_IMPORT_DECLARE_TRACE_LINE"] = str(fingerprint["lines"])
        os.environ["ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES"] = "1"
    mathlib.save_json(directory / "inputs.json", {
        "diagnostic_abstract_proofs": abstract_proofs or sliced,
        "retained_dependency_proofs": keep,
        "export": fingerprint,
        "importer": checking.fingerprint(checking.IMPORTER / "src/lean_import.cmxs"),
        "kernel": checking.fingerprint(checking.KERNEL / "_build/default/topbin/rocqworker.exe")})
    foundation = directory / "foundation"
    foundation.mkdir()
    shutil.copyfile(checking.IMPORTER / "src/Lean.v", foundation / "Lean.v")
    source = checking.full_source(export, fingerprint["lines"], line_timeout)
    if lazy_dependencies:
        source = source[:source.index("Lean Import")]
        source += (f'Set Lean Lazy Instantiation.\nLean Import "{export}" 1 {fingerprint["lines"]}.\n'
                   f'Unset Lean Lazy Instantiation.\nLean Import "{export}" '
                   f'{fingerprint["lines"]} {fingerprint["lines"] + 1}.\n')
    (directory / "Full.v").write_text(source)
    return checking.worker(directory)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("tag")
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--line-timeout", type=int, default=60)
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--lazy-dependencies", action="store_true")
    parser.add_argument("--abstract-proofs", action="store_true")
    parser.add_argument("--sliced", action="store_true")
    parser.add_argument("--keep", action="append", default=[])
    parser.add_argument("--diagnostic", action="append", default=[])
    args = parser.parse_args()
    if not args.tag or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for c in args.tag):
        parser.error("Use a unique lowercase tag")
    if not 1 <= args.line_timeout <= 600:
        parser.error("line-timeout must be between 1 and 600")
    directory = HERE / args.tag
    if args.worker:
        return worker(directory, args.line_timeout, args.trace, args.lazy_dependencies, args.abstract_proofs, args.sliced, args.keep)
    env = checking.environment(4096)
    for diagnostic in args.diagnostic:
        key, sep, value = diagnostic.partition("=")
        if not sep or not key.startswith("ROCQ_DIAGNOSTIC_"):
            parser.error("diagnostic must be ROCQ_DIAGNOSTIC_NAME=value")
        env[key] = value
    directory.mkdir()
    with (directory / "guard.log").open("x") as log:
        code = checking.wait_for_guard(
            ["bash", str(checking.GUARD), "timeout", "--kill-after=5s", "900",
             sys.executable, str(Path(__file__).resolve()), args.tag, "--worker",
             "--line-timeout", str(args.line_timeout), *(["--trace"] if args.trace else []),
             *(["--lazy-dependencies"] if args.lazy_dependencies else []),
             *(["--abstract-proofs"] if args.abstract_proofs else []),
             *(["--sliced"] if args.sliced else []),
             *[item for name in args.keep for item in ("--keep", name)]],
            env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    mathlib.save_json(directory / "result.json", {"exit_code": code})
    print(directory, "exit:", code)
    return code


if __name__ == "__main__":
    sys.exit(main())
