#!/usr/bin/env python3
"""Sequential NDJSON Mathlib checkpoints with model-free stall diagnostics."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

import run_chunked_import as chunks
import run_cslib_ndjson as direct
import run_mathlib_from_start as reference

ROOT = chunks.ROOT
STATE = ROOT / "work/mathlib-ndjson"
TRACE = ROOT / "scripts/mathlib_ndjson_trace.gdb"
SCRIPT = Path(__file__).resolve()
TARGET = "ContDiffAt.real_of_complex"
TARGET_LINE = 4_855_906


def now():
    return datetime.now(timezone.utc).isoformat()


def prepare(directory, smoke, memory_mib, interval=1_000_000, line_timeout=600):
    if interval <= 0 or line_timeout <= 0:
        raise chunks.Refused("Checkpoint interval and declaration timeout must be positive")
    interval = 400 if smoke else interval
    plan_path = directory / "checkpoints/plan.json"
    if plan_path.exists():
        plan = json.loads(plan_path.read_text())
        if (plan["interval"] != interval or plan["memory_mib"] != memory_mib
                or plan.get("line_timeout", 600) != line_timeout):
            raise chunks.Refused("Existing plan has different interval, memory or declaration timeout")
        return plan_path
    directory.mkdir(parents=True, exist_ok=True)
    chunks.save_json(directory / "progress.json", {"phase": "preparing", "updated": now()})
    source = None if smoke else reference.inspect_reference()
    export = (ROOT / "work/nat-beq-eq-def-repro/NatBeq.ndjson" if smoke else reference.NDJSON)
    profile_path = directory / "toolchain.json"
    if not profile_path.exists():
        foundation = directory / "foundation"
        foundation.mkdir(exist_ok=True)
        chunks.immutable_text(foundation / "Lean.v", (direct.checking.IMPORTER / "src/Lean.v").read_text())
        env = direct.environment(memory_mib)
        env.update(ROCQ_CHECKPOINT_LOGICAL_DIR="LeanImport",
                   ROCQ_CHECKPOINT_LOG_FILE=str(directory / "Foundation.run.log"))
        if os.environ.get("ROCQ_MEMORY_OWNER_SERVICE"):
            env["ROCQ_MEMORY_OWNER_SERVICE"] = os.environ["ROCQ_MEMORY_OWNER_SERVICE"]
        command = ["bash", str(ROOT / "work/run-checkpoint-atomic.sh"), str(foundation / "Lean.v"), "--",
                   str(direct.checking.ROCQ), "c", "-q", "-bytecode-compiler", "no",
                   "-R", str(direct.checking.STDLIB), "Stdlib",
                   "-I", str(direct.checking.IMPORTER / "src"), "-Q", str(foundation), "LeanImport"]
        with (directory / "Foundation.guard.log").open("w") as log:
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        paths = [SCRIPT, chunks.SCRIPT, TRACE, Path("/usr/bin/gdb"), foundation / "Lean.v", foundation / "Lean.vo",
                 direct.checking.IMPORTER / "src/lean_import.cmxs",
                 direct.checking.IMPORTER / "src/META.coq-lean-import",
                 Path(direct.__file__), Path(reference.__file__),
                 ROOT / "scripts/run_cslib_from_start.py"]
        paths.extend(ROOT / "work" / name for name in
                     ("run-memory-guarded.sh", "run-checkpoint-atomic.sh", "run-sealed-checkpoint.sh"))
        paths.extend(direct.checking.STDLIB.rglob("*.vo"))
        yojson = direct.checking.IMPORTER / "_build/findlib/yojson"
        paths.extend(yojson / name for name in ("META", "yojson.cmxs"))
        chunks.save_json(profile_path, {
            "format": 1, "foundation": str(foundation / "Lean.vo"),
            "importer": str(direct.checking.IMPORTER),
            "findlib_path": str(direct.checking.IMPORTER / "_build/findlib"),
            "debugger": str(TRACE), "trace_line": TARGET_LINE,
            "worker_sha256": chunks.sha(chunks.WORKER),
            "inputs": {str(path): chunks.sha(path) for path in paths}})
    plan = chunks.prepare(export, plan_path.parent, "Mathlib", interval=interval,
                          memory_mib=memory_mib, toolchain=profile_path, line_timeout=line_timeout)
    if source and plan["lines"] != source["ndjson_lines"]:
        raise chunks.Refused("Mathlib line count differs from the reference export")
    chunks.save_json(directory / "source.json", {"reference": source, "target": TARGET,
                     "target_line": TARGET_LINE, "smoke": smoke})
    return plan_path


def worker_stats(directory):
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid() or proc.joinpath("comm").read_text().strip() != "rocqworker":
                continue
            command = proc.joinpath("cmdline").read_bytes()
            if str(directory).encode() not in command or str(direct.checking.IMPORTER).encode() not in command:
                continue
            fields = dict(line.split(":", 1) for line in proc.joinpath("status").read_text().splitlines())
            parent = Path("/proc") / fields["PPid"].strip()
            return {"pid": int(proc.name), "rss_kib": int(fields["VmRSS"].split()[0]),
                    "debugged": parent.joinpath("comm").read_text().strip() == "gdb"}
        except (FileNotFoundError, ProcessLookupError, KeyError):
            continue
    return None


def monitor(directory, attempt, stop, smoke):
    log_path, offset, pending = None, 0, ""
    last_key, line, name, phase = None, None, None, None
    changed, sampled, count = time.monotonic(), 0.0, 0
    first_delay = 0.5 if smoke else 60
    while True:
        status_path = attempt / "status.json"
        if status_path.exists():
            state = json.loads(status_path.read_text())
            module = state.get("module")
            path = attempt / (module + ".run.log") if module else None
            if path != log_path:
                log_path, offset, pending = path, 0, ""
                line, name, phase = None, None, None
                changed, sampled, count = time.monotonic(), 0.0, 0
            if log_path and log_path.exists():
                with log_path.open(errors="replace") as log:
                    log.seek(offset)
                    records = (pending + log.read(1024 * 1024)).split("\n")
                    pending, offset = records.pop(), log.tell()
                for record in records:
                    match = re.match(r"line (\d+): (.+)", record)
                    if match:
                        key = (int(match[1]), match[2])
                        if key != last_key:
                            last_key = key
                            line, name = key
                            changed, sampled, count = time.monotonic(), 0.0, 0
                    match = re.match(r"\[declare ([^]]+)\] (\S+)", record)
                    if match:
                        phase = match[1] + ": " + match[2]
            worker = worker_stats(directory)
            elapsed = time.monotonic() - changed
            if (worker and worker["debugged"] and count < 3 and elapsed >= first_delay
                    and time.monotonic() - sampled >= (0.5 if smoke else 120)):
                try:
                    os.kill(worker["pid"], signal.SIGUSR1)
                    sampled, count = time.monotonic(), count + 1
                except ProcessLookupError:
                    pass
            progress = {"updated": now(), "phase": state["phase"], "module": module,
                        "line": line, "declaration": name, "declaration_phase": phase,
                        "seconds_without_new_declaration": round(elapsed, 1), "worker": worker,
                        "snapshots_requested": count, "run_log": str(log_path) if log_path else None,
                        "disk_free_gib": round(shutil.disk_usage(directory).free / 1024**3, 2)}
            checkpoint = directory / "checkpoints/progress.json"
            if checkpoint.exists():
                progress["checkpoint_through"] = json.loads(checkpoint.read_text())["next_line"] - 1
            chunks.save_json(directory / "progress.json", progress)
        if stop.wait(0.5 if smoke else 15):
            return


def run(directory, smoke, memory_mib, interval=1_000_000, line_timeout=600):
    plan_path = prepare(directory, smoke, memory_mib, interval, line_timeout)
    pause = directory / "PAUSE"
    if pause.exists():
        raise chunks.Refused("Pause requested: remove " + str(pause) + " before resuming")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    attempt = directory / "attempts" / stamp
    attempt.parent.mkdir(exist_ok=True)
    link = directory / (".latest-" + stamp)
    link.symlink_to(attempt)
    os.replace(link, directory / "latest")
    stop = threading.Event()
    watcher = threading.Thread(target=monitor, args=(directory, attempt, stop, smoke), daemon=True)
    watcher.start()
    code, error = 0, None
    try:
        chunks.run(plan_path, attempt, pause_file=pause)
    except (chunks.CompileFailed, chunks.Refused, OSError, subprocess.SubprocessError) as exc:
        code, error = getattr(exc, "code", 1), str(exc)
    finally:
        stop.set()
        watcher.join()
    result = {"completed": now(), "exit_code": code, "success": code == 0, "error": error,
              "attempt": str(attempt)}
    chunks.save_json(directory / "result.json", result)
    progress_path = directory / "progress.json"
    progress = json.loads(progress_path.read_text()) if progress_path.exists() else {}
    checkpoint = directory / "checkpoints/progress.json"
    if checkpoint.exists():
        progress["checkpoint_through"] = json.loads(checkpoint.read_text())["next_line"] - 1
    if code:
        status_path = attempt / "status.json"
        status = json.loads(status_path.read_text()) if status_path.exists() else {}
        if status.get("module"):
            log_path = attempt / (status["module"] + ".run.log")
            progress["run_log"] = str(log_path)
            if log_path.exists():
                with log_path.open("rb") as log:
                    log.seek(max(0, log_path.stat().st_size - 65536))
                    tail = log.read().decode(errors="replace")
                failures = re.findall(r"Error at line (\d+) \(for ([^)]+)\)", tail)
                if failures:
                    progress["line"], progress["declaration"] = int(failures[-1][0]), failures[-1][1]
    chunks.save_json(progress_path, {**progress, "phase": "complete" if code == 0 else "paused",
                                    "updated": now(), "worker": None, "error": error, "exit_code": code})
    print(json.dumps(result), flush=True)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("run", "status"))
    parser.add_argument("--directory", type=Path, default=STATE)
    parser.add_argument("--memory-mib", type=int, default=16384)
    parser.add_argument("--interval", type=int, default=1_000_000,
                        help="Checkpoint interval in export lines (default: 1000000)")
    parser.add_argument("--line-timeout", type=int, default=600)
    parser.add_argument("--importer", type=Path, help="Use a separately built, manifest-pinned importer")
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    directory = args.directory.resolve()
    if args.command == "status":
        print((directory / "progress.json").read_text())
        return 0
    if args.importer:
        importer = args.importer.resolve(strict=True)
        for name in ("Lean.v", "lean_import.cmxs", "META.coq-lean-import"):
            if not (importer / "src" / name).is_file():
                raise chunks.Refused("Missing importer input: " + str(importer / "src" / name))
        direct.checking.IMPORTER = importer
    return run(directory, args.smoke, args.memory_mib, args.interval, args.line_timeout)


if __name__ == "__main__":
    raise SystemExit(main())
