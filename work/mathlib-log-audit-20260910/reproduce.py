#!/usr/bin/env python3
"""Replay an original NDJSON interval in a scratch directory, after the live run stops."""
import argparse
import fcntl
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

CHECKPOINTS = ROOT / "work/mathlib-ndjson/checkpoints"
OLD = ROOT / "work/structured-arrow-repro/rocqworker.before-alias.exe"
OLD_SHA = "78cfbfb0660e84e0c62e110fd1e60b3262057b815f5f3deda10edf48fccb8ad7"
NEW_SHA = "2d631c655cb65e6b1998886414c36ef10e5a322826b613e338a15009cc090c9f"
CASES = {
    "contdiff": (4_000_000, 4_855_906, OLD, OLD_SHA),
    "analytic": (4_000_000, 4_886_805, OLD, OLD_SHA),
    "cexp": (5_000_000, 5_128_889, OLD, OLD_SHA),
    "rep-unitor": (9_000_000, 9_187_892, chunks.WORKER, NEW_SHA),
    "rep-resolution": (9_000_000, 9_239_031, chunks.WORKER, NEW_SHA),
    "reload9m": (9_000_000, 9_000_000, chunks.WORKER, NEW_SHA),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", choices=CASES)
    parser.add_argument("--run", action="store_true", help="otherwise only print the proposed source")
    parser.add_argument("--line-timeout", type=int, default=1800)
    parser.add_argument("--diagnostics", action="store_true", help="declaration CPU stages and scalar dependency counters")
    args = parser.parse_args()
    if args.line_timeout <= 0:
        parser.error("timeout must be positive")
    parent, target, worker, digest = CASES[args.case]
    module = f"MathlibTo{parent}Reload" if target == parent else f"MathlibTo{parent + 1_000_000}"
    source_path = CHECKPOINTS / (module + ".v")
    original = source_path.read_text()
    source = re.sub(r"Set Lean Line Timeout \d+\.", f"Set Lean Line Timeout {args.line_timeout}.", original)
    pattern = rf'(Lean Import "[^"]+" {parent + 1} )\d+(\.)'
    source, count = re.subn(pattern, lambda m: m[1] + str(target + 1) + m[2], source)
    if count != 1 or f"Require Import MathlibTo{parent}." not in source:
        raise ValueError("Unexpected canonical checkpoint source")
    print(json.dumps({"case": args.case, "module": module, "parent_checkpoint": parent,
                      "target": target, "worker": str(worker), "worker_sha256": digest,
                      "diagnostics": args.diagnostics}, indent=2), flush=True)
    print(source, flush=True)
    if not args.run:
        print("Dry run only. --run refuses while the full import holds its launcher lock.")
        return 0
    with (chunks.OLD_RUN / "launcher.lock").open("r") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("The full import is active; no reproduction was started")
        plan = chunks.load_plan(CHECKPOINTS / "plan.json")
        profile = chunks.generation_toolchain(plan)
        chunks.check_entries(profile["inputs"])
        if chunks.sha(worker) != digest or chunks.sha(plan["export"]) != plan["export_sha256"]:
            raise ValueError("Recorded worker/export identity changed")
        ancestors = [c for c in plan["chunks"] if c["end"] <= parent + 1]
        for chunk in ancestors:
            if chunks.verify_saved(CHECKPOINTS, chunk) is None:
                raise ValueError("Required sealed checkpoint missing: " + chunk["module"])
        chunks.check_disk(HERE, CHECKPOINTS / f"MathlibTo{parent}.vo")
        directory = Path(tempfile.mkdtemp(prefix=args.case + "-", dir=HERE))
        source_copy = directory / (module + ".v")
        source_copy.write_text(source)
        env = direct.environment(16384)
        if args.diagnostics:
            env.update(LEAN_IMPORT_DECLARE_TRACE_LINE=str(target),
                       LEAN_IMPORT_CHECKPOINT_STATS="1", ROCQ_DIAGNOSTIC_DEPENDENCY_STATS="1")
        command = ["bash", str(direct.checking.GUARD), "timeout", "7200s", str(worker),
                   "--kind=compile", "-coqlib", env["COQLIB"], "-q", "-bytecode-compiler", "no",
                   "-R", str(direct.checking.STDLIB), "Stdlib",
                   "-Q", str(CHECKPOINTS), "", "-Q", str(directory), "",
                   "-Q", str(ROOT / "work/mathlib-ndjson/foundation"), "LeanImport",
                   "-I", str(direct.checking.IMPORTER / "src"), str(source_copy)]
        record = {"command": command, "source": source, "worker_sha256": digest,
                  "export_sha256": plan["export_sha256"], "diagnostics": args.diagnostics,
                  "profile_sha256": chunks.sha(ROOT / "work/mathlib-ndjson/toolchain.json"),
                  "ancestors": {c["module"]: chunks.sha(CHECKPOINTS / (c["module"] + ".vo"))
                                for c in ancestors}}
        (directory / "invocation.json").write_text(json.dumps(record, indent=2) + "\n")
        print("Log:", directory / "run.log", flush=True)
        started = time.monotonic()
        with (directory / "run.log").open("x") as log:
            result = subprocess.run(command, cwd=directory, env=env, stdout=log, stderr=subprocess.STDOUT)
        (directory / "result.json").write_text(json.dumps({"exit_code": result.returncode,
            "wall_seconds": time.monotonic() - started,
            "vo_saved": source_copy.with_suffix(".vo").is_file()}, indent=2) + "\n")
        return result.returncode


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, chunks.Refused) as error:
        print(error, file=sys.stderr)
        raise SystemExit(2)
