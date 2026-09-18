#!/usr/bin/env python3
"""One manually monitored, guarded import from line 1; no checkpoints or repairs."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).resolve()
KERNEL = ROOT / "_worktrees/rocq/compact-peano-view"
IMPORTER = ROOT / "_worktrees/rocq-lean-import/compact-peano-importer-current"
STDLIB = ROOT / "_worktrees/rocq/stdlib-int32-repro/theories"
EXPORT = ROOT / "_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export"
RUNS = ROOT / "work/cslib-from-start"
GUARD = ROOT / "work/run-memory-guarded.sh"
PREFIX = KERNEL / "_build/install/default"
ROCQ = PREFIX / "bin/rocq"


def fingerprint(path):
    """Hash and count logical lines in one bounded-memory pass."""
    digest, lines, last = hashlib.sha256(), 0, b""
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
            lines += block.count(b"\n")
            last = block[-1:]
    return {"sha256": digest.hexdigest(), "lines": lines + int(bool(last) and last != b"\n")}


def git_state(path):
    def git(*args):
        return subprocess.check_output(["git", "-C", str(path), *args], text=True).strip()
    return {"head": git("rev-parse", "HEAD"), "status": git("status", "--short")}


def environment(memory_mib):
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("LEAN_IMPORT_", "ROCQ_", "_ROCQ_", "ROCQLKA_"))
           and key not in ("COQPATH", "ROCQPATH", "COQCORELIB", "ROCQCORELIB")}
    env.update(PATH=str(PREFIX / "bin") + os.pathsep + env.get("PATH", ""),
               OCAMLPATH=str(PREFIX / "lib"), COQBIN=str(PREFIX / "bin") + "/",
               COQLIB=str(PREFIX / "lib/coq"), ROCQLIB=str(PREFIX / "lib/coq"),
               CAML_LD_LIBRARY_PATH=str(PREFIX / "lib/stublibs"),
               OCAMLRUNPARAM="s=4M,o=80,i=15,a=2,v=0,b",
               ROCQ_MEMORY_MAX_KIB=str(memory_mib * 1024),
               ROCQ_MEMORY_HIGH_KIB=str(memory_mib * 1024),
               ROCQ_MAX_RSS_KIB=str(memory_mib * 1024 * 15 // 16),
               ROCQ_MIN_AVAILABLE_KIB="3145728", ROCQ_MEMORY_SWAP_MAX_KIB="0",
               ROCQ_ALLOW_EXTERNAL_ROCQ="0", ROCQ_STACK_KIB="262144",
               ROCQ_MEMORY_POLL_SECONDS="0.25", ROCQ_MEMORY_STATUS_SECONDS="15")
    return env


def full_source(export, lines, timeout):
    if any(ord(char) < 32 for char in str(export)):
        raise ValueError("Export path contains control characters")
    quoted = str(export).replace('"', '""')
    return f'''From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout {timeout}.
Lean Import "{quoted}" 1 {lines + 1}.
'''


def worker(directory):
    # The hidden entrypoint cannot launch an unguarded compiler.
    if (os.environ.get("_ROCQ_MEMORY_GUARD_SCOPED") != "1"
            or not Path("/proc/self/cgroup").read_text().strip().endswith("/rocq-lean-import-heavy.scope")):
        raise ValueError("Internal worker requires the memory guard's scope")
    foundation = directory / "foundation"
    common = [str(ROCQ), "c", "-q", "-bytecode-compiler", "no", "-R", str(STDLIB), "Stdlib",
              "-I", str(IMPORTER / "src"), "-Q", str(foundation), "LeanImport"]
    for source, log in ((foundation / "Lean.v", "foundation.log"), (directory / "Full.v", "Full.run.log")):
        print("Checking", source.name, flush=True)
        with (directory / log).open("x") as output:
            code = subprocess.run([*common, source.name], cwd=source.parent,
                                  stdout=output, stderr=subprocess.STDOUT).returncode
        if code:
            return code
        if not source.with_suffix(".vo").is_file():
            raise ValueError("Compiler returned success without " + str(source.with_suffix(".vo")))
    return 0


def wait_for_guard(command, **kwargs):
    """Forward cancellation once, then let the guard finish cleaning up."""
    process, cancelled, forwarded = None, None, False

    def forward_pending():
        nonlocal forwarded
        if process is not None and cancelled is not None and not forwarded:
            forwarded = True
            try:
                process.send_signal(cancelled)
            except ProcessLookupError:
                pass

    def cancel(signum, _frame):
        nonlocal cancelled
        if cancelled is None:
            cancelled = signum
            forward_pending()

    previous = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        for sig in previous:
            signal.signal(sig, cancel)
        # The foreground parent relays terminal cancellation exactly once.
        process = subprocess.Popen(command, start_new_session=True, **kwargs)
        forward_pending()
        code = process.wait()
        return 128 + cancelled if cancelled is not None else (128 - code if code < 0 else code)
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def launch(args):
    if os.environ.get("_ROCQ_MEMORY_GUARD_SCOPED"):
        raise ValueError("Do not nest this runner inside another guarded job")
    export = args.export.resolve(strict=True)
    inputs = [ROCQ, KERNEL / "_build/default/topbin/rocqworker.exe",
              IMPORTER / "src/lean_import.cmxs", IMPORTER / "src/META.coq-lean-import",
              IMPORTER / "src/Lean.v", GUARD]
    for path in [export, *inputs, STDLIB / "Numbers/BinNums.vo"]:
        if not path.is_file():
            raise ValueError("Required input is missing: " + str(path))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = (args.directory or RUNS / stamp).absolute()
    if os.path.lexists(directory):
        raise ValueError("Run directory must be new: " + str(directory))
    directory = directory.resolve()
    command = ["bash", str(GUARD), sys.executable, str(SCRIPT), "--worker", str(directory)]
    if args.dry_run:
        print(json.dumps({"directory": str(directory), "export": str(export), "start_line": 1,
                          "end": "EOF + 1 (counted at launch)", "memory_mib": args.memory_mib,
                          "line_timeout": args.line_timeout, "command": command}, indent=2))
        return 0
    manifest = {"mode": "manual-from-line-1", "created": stamp, "export": str(export),
                "export_fingerprint": fingerprint(export), "kernel": git_state(KERNEL),
                "importer": git_state(IMPORTER), "inputs": {str(p): fingerprint(p)["sha256"] for p in inputs},
                "memory_mib": args.memory_mib, "line_timeout": args.line_timeout}
    if not manifest["export_fingerprint"]["lines"]:
        raise ValueError("Export is empty")
    source = full_source(export, manifest["export_fingerprint"]["lines"], args.line_timeout)
    directory.mkdir(parents=True)
    (directory / "foundation").mkdir()
    shutil.copyfile(IMPORTER / "src/Lean.v", directory / "foundation/Lean.v")
    (directory / "Full.v").write_text(source)
    (directory / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    RUNS.mkdir(parents=True, exist_ok=True)
    link = RUNS / (".latest-" + stamp)
    link.symlink_to(directory)
    os.replace(link, RUNS / "latest")
    for name in ("guard.log", "foundation.log", "Full.run.log"):
        print(name + ":", directory / name, flush=True)
    with (directory / "guard.log").open("x") as output:
        code = wait_for_guard(command, cwd=ROOT, env=environment(args.memory_mib),
                              stdout=output, stderr=subprocess.STDOUT)
    result = {"exit_code": code, "completed": datetime.now(timezone.utc).isoformat(),
              "success": code == 0 and (directory / "Full.vo").is_file()}
    if code == 0 and not result["success"]:
        code = result["exit_code"] = 2
    (directory / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print("Exit code:", code, "— result:", directory / "result.json", flush=True)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export", type=Path, default=EXPORT)
    parser.add_argument("--directory", type=Path, help="New output directory; never reused")
    parser.add_argument("--memory-mib", type=int, default=16384)
    parser.add_argument("--line-timeout", type=int, default=600)
    parser.add_argument("--dry-run", action="store_true", help="Print plan without hashing, creating or launching")
    parser.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 256 <= args.memory_mib <= 16384 or not 1 <= args.line_timeout <= 600:
        parser.error("memory-mib must be 256..16384; line-timeout must be 1..600")
    try:
        return worker(args.worker) if args.worker else launch(args)
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print("Manual import:", exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
