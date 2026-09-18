#!/usr/bin/env python3
"""Trace the original Mathlib failure, with an optional reusable prefix."""

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_from_start as checking
import run_mathlib_from_start as mathlib

LINE = 4855902
EXPORT_SHA = "b5dcda65085e60f71519941f7d92523b1f8fb85a0a132b9b90f8a2e3ca2ffc88"
STATE = HERE / "faithful"
ATOMIC = ROOT / "work/run-checkpoint-atomic.sh"
SEALED = ROOT / "work/run-sealed-checkpoint.sh"


def immutable(path, content):
    if path.exists():
        if path.read_text() != content:
            raise ValueError(f"Inputs changed; refusing checkpoint reuse: {path}")
    else:
        with path.open("x") as output:
            output.write(content)


def sources():
    full = checking.full_source(mathlib.EXPORT, LINE, 600)
    settings = full[:full.index("Lean Import ")]
    prefix = settings + f'Lean Import "{mathlib.EXPORT}" 1 {LINE}.\n'
    target = settings.replace("Require Import Lean.\n", "Require Import Lean.\nRequire Import ContDiffPrefix.\n")
    target += f'Lean Import "{mathlib.EXPORT}" {LINE} {LINE + 1}.\n'
    return prefix, target, full


def wait_for_checkpoint(command, **kwargs):
    process, cancelled = None, None

    def cancel(signum, _frame):
        nonlocal cancelled
        if cancelled is None:
            cancelled = signum
            if process is not None:
                try:
                    os.killpg(process.pid, signum)
                except ProcessLookupError:
                    pass

    previous = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        for sig in previous:
            signal.signal(sig, cancel)
        process = subprocess.Popen(command, start_new_session=True, **kwargs)
        if cancelled is not None:
            try:
                os.killpg(process.pid, cancelled)
            except ProcessLookupError:
                pass
        code = process.wait()
        return 128 + cancelled if cancelled is not None else (128 - code if code < 0 else code)
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def compile_source(source, logs, env, *, manifest=None, logical=None, trace=False):
    name = source.stem
    command = ["timeout", "--kill-after=10s", "8h", str(checking.ROCQ),
               "c", "-q", "-bytecode-compiler", "no",
               "-R", str(checking.STDLIB), "Stdlib",
               "-I", str(checking.IMPORTER / "src"),
               "-Q", str(STATE / "foundation"), "LeanImport",
               "-Q", str(STATE / "prefix"), ""]
    environment = dict(env, ROCQ_CHECKPOINT_LOG_FILE=str(logs / f"{name}.run.log"),
                       LEAN_IMPORT_EXCEPTION_BACKTRACE="1", LEAN_IMPORT_CHECKPOINT_STATS="1")
    if manifest:
        environment["ROCQ_CHECKPOINT_INPUTS_FILE"] = str(manifest)
    if logical:
        environment["ROCQ_CHECKPOINT_LOGICAL_DIR"] = logical
    if trace:
        environment["LEAN_IMPORT_DECLARE_TRACE_LINE"] = str(LINE)
        environment["ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES"] = "1"
    print(f"Checking {name} — {logs / (name + '.run.log')}", flush=True)
    with (logs / f"{name}.guard.log").open("w") as output:
        code = wait_for_checkpoint(
            ["bash", str(SEALED if manifest else ATOMIC), str(source), "--", *command],
            cwd=ROOT, env=environment, stdout=output, stderr=output)
    if code == 0 and not source.with_suffix(".vo").is_file():
        raise ValueError(f"Compiler succeeded without producing {source.with_suffix('.vo')}")
    return code


def run(args):
    if os.environ.get("_ROCQ_MEMORY_GUARD_SCOPED"):
        raise ValueError("Do not run inside another memory guard")
    if args.dry_run:
        print(json.dumps({"export": str(mathlib.EXPORT), "target": "ContDiffAt.real_of_complex",
                          "prefix": [1, LINE], "target_range": [LINE, LINE + 1],
                          "until_is_exclusive": True, "from_start": args.from_start,
                          "memory_mib": args.memory_mib, "line_timeout": 600,
                          "logs": str(STATE / "latest")}, indent=2))
        return 0
    STATE.mkdir(exist_ok=True)
    with (STATE / "runner.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return locked_run(args)


def locked_run(args):
    if shutil.disk_usage(STATE).free < 6 * 1024**3:
        raise ValueError("Need at least 6 GiB of free disk for checkpoint staging")
    print("Verifying the original export and checkpoint inputs…", flush=True)
    inputs = [mathlib.EXPORT, checking.ROCQ,
              checking.KERNEL / "_build/default/topbin/rocqworker.exe",
              checking.IMPORTER / "src/lean_import.cmxs",
              checking.IMPORTER / "src/META.coq-lean-import",
              checking.IMPORTER / "src/Lean.v", checking.GUARD,
              ATOMIC, SEALED, checking.SCRIPT, Path(__file__).resolve()]
    stdlib = sorted(checking.STDLIB.rglob("*.vo"))
    if not stdlib:
        raise ValueError("Compiled Rocq standard library is missing")
    hashes = {str(p): checking.fingerprint(p)["sha256"] for p in [*inputs, *stdlib]}
    if hashes[str(mathlib.EXPORT)] != EXPORT_SHA:
        raise ValueError("Export differs from the original failed Mathlib run")
    manifest = STATE / "inputs.sha256"
    immutable(manifest, "".join(f"{digest}  {path}\n" for path, digest in hashes.items()))
    foundation = STATE / "foundation"
    prefix_dir = STATE / "prefix"
    foundation.mkdir(exist_ok=True)
    prefix_dir.mkdir(exist_ok=True)
    immutable(foundation / "Lean.v", (checking.IMPORTER / "src/Lean.v").read_text())
    prefix, target, full = sources()
    immutable(prefix_dir / "ContDiffPrefix.v", prefix)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    attempt = STATE / stamp
    attempt.mkdir()
    modules = ["Lean", "Full"] if args.from_start else ["Lean", "ContDiffPrefix", "Target"]
    for module in modules:
        for suffix in ("run", "guard"):
            (attempt / f"{module}.{suffix}.log").touch()
    link = STATE / (".latest-" + stamp)
    link.symlink_to(attempt)
    os.replace(link, STATE / "latest")
    mode = "from-start" if args.from_start else "saved-prefix"
    (attempt / "run.json").write_text(json.dumps({
        "mode": mode, "memory_mib": args.memory_mib, "line_timeout": 600,
        "export": str(mathlib.EXPORT), "target_line": LINE,
        "kernel": checking.git_state(checking.KERNEL),
        "importer": checking.git_state(checking.IMPORTER)}, indent=2) + "\n")
    env = checking.environment(args.memory_mib)
    code = compile_source(foundation / "Lean.v", attempt, env,
                          manifest=manifest, logical="LeanImport")
    # Bind the prefix to its freshly compiled foundation as well as the binaries.
    if code == 0:
        prefix_manifest = STATE / "prefix-inputs.sha256"
        lean_vo = foundation / "Lean.vo"
        immutable(prefix_manifest, manifest.read_text()
                  + f'{checking.fingerprint(lean_vo)["sha256"]}  {lean_vo}\n')
        if not args.from_start:
            code = compile_source(prefix_dir / "ContDiffPrefix.v", attempt, env,
                                  manifest=prefix_manifest)
        if code == 0:
            source = attempt / ("Full.v" if args.from_start else "Target.v")
            immutable(source, full if args.from_start else target)
            code = compile_source(source, attempt, env, trace=True)
    (attempt / "result.json").write_text(json.dumps({"exit_code": code, "mode": mode}) + "\n")
    print(f"Exit {code}; logs: {attempt}", flush=True)
    if code == 0:
        print("Target passed in this mode; the original timeout was not reproduced.", flush=True)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--from-start", action="store_true",
                        help="Check through the target in one import, without loading a prefix")
    parser.add_argument("--memory-mib", type=int, default=8192)
    args = parser.parse_args()
    if not 4096 <= args.memory_mib <= 16384:
        parser.error("memory-mib must be between 4096 and 16384")
    try:
        return run(args)
    except (OSError, ValueError) as exc:
        print(f"Diagnostic run: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
