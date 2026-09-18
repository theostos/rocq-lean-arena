#!/usr/bin/env python3
"""Bounded checks of the cache restoration, without resuming Mathlib."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

KERNEL = ROOT / "_worktrees/rocq/compact-peano-view"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reload-only", action="store_true")
    args = parser.parse_args()
    with (chunks.OLD_RUN / "launcher.lock").open("r") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        stage = Path(tempfile.mkdtemp(prefix="checks-", dir=HERE))
        print(stage, flush=True)
        env = direct.environment(4096)
        env["OCAMLPATH"] = str(KERNEL / "_build/install/default/lib") + os.pathsep + env["OCAMLPATH"]
        results = []

        def run(name, command, *, guard=True):
            if guard:
                command = ["bash", str(direct.checking.GUARD), "timeout", "180s", *command]
            with (stage / (name + ".log")).open("x") as log:
                result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
            results.append({"check": name, "exit_code": result.returncode, "command": command})
            (stage / "results.json").write_text(json.dumps(results, indent=2) + "\n")
            print(name, result.returncode, flush=True)
            if result.returncode:
                raise RuntimeError("Failed: " + str(stage / (name + ".log")))

        if not args.reload_only:
            compiler = ["ocamlfind", "ocamlopt", "-rectypes", "-thread", "-package", "rocq-runtime.kernel"]
            source = KERNEL / "test-suite/unit-tests/kernel/constant_deps.ml"
            run("dependencies-build", [*compiler, "-c", str(source), "-o", str(stage / "constant_deps.cmx")])
            run("dependencies-link", [*compiler, "-linkpkg", str(stage / "constant_deps.cmx"),
                                      "-o", str(stage / "constant_deps.exe")])
            run("dependencies", [str(stage / "constant_deps.exe")])
            run("regressions", [sys.executable, str(ROOT / "work/structured-arrow-repro/validate.py")], guard=False)
        source = stage / "Reload9M.v"
        source.write_text("From LeanImport Require Import Lean.\n"
                          "Set Kernel Conversion Dep Heuristic.\n"
                          "Require Import MathlibTo9000000.\n"
                          "Goal forall A : Type, A -> A. Proof. intros A x. exact x. Qed.\n")
        run("reload9m", [str(chunks.WORKER), "--kind=compile", "-coqlib", env["COQLIB"],
            "-q", "-bytecode-compiler", "no", "-R", str(direct.checking.STDLIB), "Stdlib",
            "-Q", str(ROOT / "work/mathlib-ndjson/checkpoints"), "",
            "-Q", str(ROOT / "work/mathlib-ndjson/foundation"), "LeanImport",
            "-I", str(direct.checking.IMPORTER / "src"), "-Q", str(stage), "CacheRestore", str(source)])
        (stage / "identity.json").write_text(json.dumps({
            "worker_sha256": chunks.sha(chunks.WORKER),
            "environ_sha256": chunks.sha(KERNEL / "kernel/environ.ml"),
            "importer_sha256": chunks.sha(direct.checking.IMPORTER / "src/lean_import.cmxs"),
            "scope": "9M reload only" if args.reload_only else "dependency semantics, 20 regressions, 9M reload",
        }, indent=2) + "\n")
        print("Checks passed; full Mathlib remains paused.", flush=True)


if __name__ == "__main__":
    main()
