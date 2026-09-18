#!/usr/bin/env python3
"""Reuse the Arena reference Mathlib export and check it from line 1."""

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import run_cslib_from_start as checking

ROOT = checking.ROOT
SCRIPT = Path(__file__).resolve()
RUNS = ROOT / "work/mathlib-from-start"
ARENA = ROOT / "_deps/lean-kernel-arena"
NDJSON = ARENA / "_build/tests/mathlib.ndjson"
STATS = ARENA / "_build/tests/mathlib.stats.json"
SPEC = ARENA / "tests/mathlib.yaml"
CONVERTER = ARENA / "checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py"
TOOLCHAIN = "leanprover/lean4:v4.29.0"
LEAN_REVISION = "98dc76e3c0a9b856c9b98726b713fb04fab16740"
REVISION = "8a178386ffc0f5fef0b77738bb5449d50efeea95"
BUNDLE = ROOT / "work/library-exports/mathlib-4.29/full"
EXPORT = BUNDLE / "Mathlib.lean-export"
GIB = 1024**3


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def require_guard():
    if (os.environ.get("_ROCQ_MEMORY_GUARD_SCOPED") != "1"
            or not Path("/proc/self/cgroup").read_text().strip().endswith("/rocq-lean-import-heavy.scope")):
        raise ValueError("Internal worker requires the memory guard's scope")


def checker_inputs():
    return [checking.ROCQ, checking.KERNEL / "_build/default/topbin/rocqworker.exe",
            checking.IMPORTER / "src/lean_import.cmxs",
            checking.IMPORTER / "src/META.coq-lean-import", checking.IMPORTER / "src/Lean.v",
            checking.GUARD, checking.SCRIPT, SCRIPT]


def reference_inputs():
    return [NDJSON, STATS, SPEC, CONVERTER]


def inspect_reference():
    stats = json.loads(STATS.read_text())
    with NDJSON.open("rb") as source:
        metadata = json.loads(source.readline(1024 * 1024))["meta"]
    expected = {"url": "https://github.com/leanprover-community/mathlib4",
                "ref": "v4.29.0", "rev": REVISION, "module": "Mathlib"}
    spec = dict(line.split(": ", 1) for line in SPEC.read_text().splitlines()
                if any(line.startswith(key + ": ") for key in expected))
    if spec != expected:
        raise ValueError("Arena Mathlib specification does not match the pinned 4.29 reference")
    if (metadata["lean"] != {"version": "4.29.0", "githash": LEAN_REVISION}
            or stats["lean_version"] != "4.29.0" or stats["lean_githash"] != LEAN_REVISION
            or stats["lean4export_version"] != metadata["exporter"]["version"]
            or stats["name"] != "mathlib"
            or stats["source_url"] != expected["url"] + "/tree/" + REVISION):
        raise ValueError("Existing NDJSON metadata does not match the pinned Mathlib reference")
    if stats["size"] != NDJSON.stat().st_size or stats["lines"] <= 0:
        raise ValueError("Existing NDJSON size does not match its export statistics")
    return {"toolchain": TOOLCHAIN, "mathlib_revision": REVISION,
            "source_url": stats["source_url"], "metadata": metadata,
            "ndjson_bytes": stats["size"], "ndjson_lines": stats["lines"]}


def check_inputs(inputs):
    for path, digest in inputs.items():
        if checking.fingerprint(Path(path))["sha256"] != digest:
            raise ValueError("Input changed: " + path)


def disk_gate(directory, required):
    if shutil.disk_usage(directory).free < required:
        raise ValueError("Insufficient free disk space: need %.1f GiB" % (required / GIB))


def convert_reference(output):
    command = [sys.executable, str(CONVERTER), str(NDJSON), str(output)]
    process = subprocess.Popen(command, env=dict(os.environ, ROCQLKA_NDJSON_STREAM="1"))
    try:
        while True:
            disk_gate(output.parent, 3 * GIB)
            try:
                code = process.wait(timeout=1)
                break
            except subprocess.TimeoutExpired:
                pass
        if code:
            raise subprocess.CalledProcessError(code, command)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def prepare_export():
    require_guard()
    source = inspect_reference()
    print("Verifying existing Lean 4.29 reference NDJSON", flush=True)
    fingerprints = {str(path): checking.fingerprint(path) for path in reference_inputs()}
    if fingerprints[str(NDJSON)]["lines"] != source["ndjson_lines"]:
        raise ValueError("Existing NDJSON line count does not match its export statistics")
    inputs = {path: value["sha256"] for path, value in fingerprints.items()}
    if BUNDLE.exists():
        print("Verifying cached hint-preserving conversion", flush=True)
        record = json.loads((BUNDLE / "provenance.json").read_text())
        if record["source"] != source or record["inputs"] != inputs:
            raise ValueError("Cached Mathlib conversion inputs changed; cache was not replaced")
        fingerprint = checking.fingerprint(EXPORT)
        if not fingerprint["lines"] or fingerprint != record["export_fingerprint"]:
            raise ValueError("Cached Mathlib export changed; cache was not replaced")
        return source, fingerprint
    disk_gate(ROOT, 12 * GIB)
    BUNDLE.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".full.stage-", dir=BUNDLE.parent))
    print("Converting existing NDJSON into " + str(stage), flush=True)
    export = stage / "Mathlib.lean-export"
    convert_reference(export)
    check_inputs(inputs)
    if inspect_reference() != source:
        raise ValueError("Mathlib reference changed during conversion")
    fingerprint = checking.fingerprint(export)
    if not fingerprint["lines"]:
        raise ValueError("Mathlib export is empty")
    save_json(stage / "provenance.json",
              {"source": source, "module": "Mathlib", "inputs": inputs,
               "export_fingerprint": fingerprint, "ndjson": str(NDJSON),
               "converter": str(CONVERTER), "streaming": True})
    # Failed stages remain diagnostic artifacts, never reusable exports.
    stage.rename(BUNDLE)
    return source, fingerprint


def worker(directory):
    require_guard()
    settings = json.loads((directory / "settings.json").read_text())
    inputs = {str(path): checking.fingerprint(path)["sha256"] for path in checker_inputs()}
    source, fingerprint = prepare_export()
    check_inputs(inputs)
    disk_gate(ROOT, 3 * GIB)
    manifest = {"mode": "manual-from-line-1", "library": "Mathlib", "source": source,
                "created": settings["created"], "export": str(EXPORT),
                "export_fingerprint": fingerprint,
                "kernel": checking.git_state(checking.KERNEL),
                "importer": checking.git_state(checking.IMPORTER), "inputs": inputs,
                "memory_mib": settings["memory_mib"], "line_timeout": settings["line_timeout"]}
    save_json(directory / "manifest.json", manifest)
    foundation = directory / "foundation"
    foundation.mkdir()
    shutil.copyfile(checking.IMPORTER / "src/Lean.v", foundation / "Lean.v")
    (directory / "Full.v").write_text(
        checking.full_source(EXPORT, fingerprint["lines"], settings["line_timeout"]))
    print("Checking Mathlib from line 1 through EOF (%s lines)" % fingerprint["lines"], flush=True)
    code = checking.worker(directory)
    check_inputs(inputs)
    return code


def launch(args):
    if os.environ.get("_ROCQ_MEMORY_GUARD_SCOPED"):
        raise ValueError("Do not nest this runner inside another guarded job")
    for path in [*checker_inputs(), checking.STDLIB / "Numbers/BinNums.vo", *reference_inputs()]:
        if not path.is_file():
            raise ValueError("Required input is missing: " + str(path))
    inspect_reference()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = (args.directory or RUNS / stamp).absolute()
    if os.path.lexists(directory):
        raise ValueError("Run directory must be new: " + str(directory))
    directory = directory.resolve()
    command = ["bash", str(checking.GUARD), sys.executable, str(SCRIPT), "--worker", str(directory)]
    if args.dry_run:
        print(json.dumps({"library": "Mathlib", "toolchain": TOOLCHAIN,
                          "mathlib_revision": REVISION, "ndjson": str(NDJSON), "export": str(EXPORT),
                          "export_action": "verify cache" if BUNDLE.exists()
                          else "convert existing reference NDJSON (no Lean export or build)",
                          "directory": str(directory), "start_line": 1, "end": "EOF",
                          "memory_mib": args.memory_mib, "line_timeout": args.line_timeout,
                          "checkpoints": False, "automatic_repairs": False, "command": command}, indent=2))
        return 0
    RUNS.mkdir(parents=True, exist_ok=True)
    with (RUNS / "runner.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("A manual Mathlib run already owns the runner") from None
        directory.mkdir(parents=True)
        save_json(directory / "settings.json", {"created": stamp, "memory_mib": args.memory_mib,
                                                "line_timeout": args.line_timeout})
        link = RUNS / (".latest-" + stamp)
        link.symlink_to(directory)
        os.replace(link, RUNS / "latest")
        for name in ("guard.log", "foundation.log", "Full.run.log"):
            print(name + ":", directory / name, flush=True)
        with (directory / "guard.log").open("x") as output:
            code = checking.wait_for_guard(command, cwd=ROOT, env=checking.environment(args.memory_mib),
                                          stdout=output, stderr=subprocess.STDOUT)
        success = code == 0 and (directory / "Full.vo").is_file()
        if code == 0 and not success:
            code = 2
        save_json(directory / "result.json", {"exit_code": code, "success": success,
                                             "completed": datetime.now(timezone.utc).isoformat()})
        print("Exit code:", code, "— result:", directory / "result.json", flush=True)
        return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
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
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("Manual Mathlib import:", exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
