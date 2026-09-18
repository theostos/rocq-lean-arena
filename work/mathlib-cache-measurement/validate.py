#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_ndjson as direct

stage = Path(tempfile.mkdtemp(prefix="validation-", dir=HERE))
print(stage, flush=True)
env = direct.environment(4096)
kernel = ROOT / "_worktrees/rocq/compact-peano-view"
env["OCAMLPATH"] = str(kernel / "_build/install/default/lib") + os.pathsep + env["OCAMLPATH"]
compiler = ["ocamlfind", "ocamlopt", "-rectypes", "-thread", "-package", "rocq-runtime.kernel", "-I", str(stage)]


def run(name, command):
    with (stage / (name + ".log")).open("x") as log:
        result = subprocess.run(["bash", str(direct.checking.GUARD), "timeout", "120s", *command],
            cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
    print(name, result.returncode, flush=True)
    if result.returncode:
        raise RuntimeError(str(stage / (name + ".log")))


run("compile-dependencies", [*compiler, "-c", str(kernel / "test-suite/unit-tests/kernel/constant_deps.ml"),
    "-o", str(stage / "constant_deps.cmx")])
run("compile-interruption", [*compiler, "-c", str(HERE / "interrupt_profile.ml"), "-o", str(stage / "interrupt_profile.cmx")])
run("link", [*compiler, "-linkpkg", str(stage / "constant_deps.cmx"), str(stage / "interrupt_profile.cmx"),
    "-o", str(stage / "test.exe")])
run("disabled", [str(stage / "test.exe")])
env["ROCQ_MEASURE_DEPENDENCIES"] = "1"
run("enabled", [str(stage / "test.exe")])
log = (stage / "enabled.log").read_text()
assert "interrupted_queries=1" in log and "interrupted_builds=1" in log and "build_depth=0" in log
(stage / "result.json").write_text(json.dumps({"success": True, "timer_exceptions_counted": True}) + "\n")
print("Cache semantics and interrupted timers passed.", flush=True)
