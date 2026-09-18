#!/usr/bin/env python3
"""Check the original target and its requested dependencies, not the full interval."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_ndjson as direct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kernel", choices=("baseline", "candidate"))
    args = parser.parse_args()
    worker = (HERE / "rocqworker.before-alias.exe" if args.kernel == "baseline" else
              ROOT / "_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe")
    directory = Path(tempfile.mkdtemp(prefix=args.kernel + "-target-", dir=HERE))
    source = directory / "Target.v"
    shutil.copy2(HERE / source.name, source)
    env = direct.environment(4096)
    env["LEAN_IMPORT_EXCEPTION_BACKTRACE"] = "1"
    print(directory, flush=True)
    command = ["bash", str(direct.checking.GUARD), "timeout", "240s", str(worker),
               "--kind=compile", "-coqlib", env["COQLIB"], "-q", "-bytecode-compiler", "no",
               "-R", str(direct.checking.STDLIB), "Stdlib",
               "-Q", str(ROOT / "work/mathlib-ndjson/checkpoints"), "",
               "-Q", str(ROOT / "work/mathlib-ndjson/foundation"), "LeanImport",
               "-I", str(direct.checking.IMPORTER / "src"), "-Q", str(directory), "TargetDiagnostic",
               str(source)]
    with (directory / "run.log").open("x") as log:
        result = subprocess.run(command, cwd=directory, env=env, stdout=log, stderr=subprocess.STDOUT)
    report = {"kernel": args.kernel, "worker_sha256": hashlib.sha256(worker.read_bytes()).hexdigest(),
              "exit_code": result.returncode, "log": str(directory / "run.log"),
              "scope": "target and requested dependencies; intermediate declarations are deferred"}
    (directory / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
