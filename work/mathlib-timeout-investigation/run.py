#!/usr/bin/env python3
"""One sequential timeout investigation, using existing diagnostics only."""
import fcntl
from functools import lru_cache
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASE = ROOT / "work/mathlib-cache-measurement"
sys.path.insert(0, str(ROOT / "scripts"))
import run_chunked_import as chunks
import run_cslib_ndjson as direct
from analyze import summarize

TARGET = "Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq"


def sample_worker(state, stop):
    while not stop.wait(20):
        pid, debugger = state.get("pid"), state.get("debugger")
        if not state.get("target") or not pid:
            continue
        try:
            status = dict(line.split(":", 1) for line in Path(f"/proc/{pid}/status").read_text().splitlines())
            command = Path(f"/proc/{pid}/cmdline").read_bytes()
            if int(status["TracerPid"]) != debugger or str(BASE / "rocqworker.profile.exe").encode() not in command:
                continue
            os.kill(pid, signal.SIGUSR1)
        except (FileNotFoundError, ProcessLookupError):
            continue


def main():
    print("Waiting for the existing measurement to release the single-worker lock.", flush=True)
    with (chunks.OLD_RUN / "launcher.lock").open("r") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        checkpoints = ROOT / "work/mathlib-ndjson/checkpoints"
        plan = json.loads((checkpoints / "plan.json").read_text())
        identity = json.loads((BASE / "worker.json").read_text())
        worker = BASE / "rocqworker.profile.exe"
        chunks.sha = lru_cache(maxsize=None)(chunks.sha)
        if chunks.sha(worker) != identity["sha256"] or chunks.sha(chunks.WORKER) != identity["base_worker_sha256"]:
            raise RuntimeError("Worker changed since the baseline measurement")
        chunks.check_entries(chunks.generation_toolchain(plan)["inputs"])
        if chunks.sha(Path(plan["export"])) != plan["export_sha256"]:
            raise RuntimeError("Export changed")
        ancestors = [c for c in plan["chunks"] if c["end"] <= 9_000_001]
        for chunk in ancestors:
            if chunks.verify_saved(checkpoints, chunk) is None:
                raise RuntimeError("Missing checkpoint: " + chunk["module"])
        chunks.check_disk(HERE, checkpoints / "MathlibTo9000000.vo")
        stage = Path(tempfile.mkdtemp(prefix="run-", dir=HERE))
        link = HERE / ".latest-new"
        link.symlink_to(stage.name)
        os.replace(link, HERE / "latest")
        source = (checkpoints / "MathlibTo10000000.v").read_text()
        source, count = re.subn(r'(Lean Import "[^"]+" 9000001 )10000001\.', r'\g<1>9239032.', source)
        if count != 1 or "Set Lean Line Timeout 1800." not in source:
            raise RuntimeError("Unexpected original source")
        source_path = stage / "MathlibTo10000000.v"
        source_path.write_text(source)
        env = direct.environment(16384)
        env.update(ROCQ_MEASURE_DEPENDENCIES="1", LEAN_IMPORT_DECLARE_TRACE_LINE="9239031",
                   LEAN_IMPORT_EXCEPTION_BACKTRACE="1", LEAN_IMPORT_CHECKPOINT_STATS="1",
                   ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES="1", ROCQ_DIAGNOSTIC_DEPENDENCY_STATS="1",
                   ROCQ_PROFILE_COMPONENTS="Typeops.execute,check-wf-univs,HConstr.of_constr,Constr.hcons")
        if os.environ.get("ROCQ_MEMORY_OWNER_SERVICE"):
            env["ROCQ_MEMORY_OWNER_SERVICE"] = os.environ["ROCQ_MEMORY_OWNER_SERVICE"]
        command = ["bash", str(direct.checking.GUARD), "timeout", "--kill-after=5s", "7200s",
            "/usr/bin/gdb", "-q", "-nx", "-nh", "--batch", "--return-child-result", "-x", str(HERE / "trace.gdb"), "--args",
            str(worker), "--kind=compile", "-coqlib", env["COQLIB"], "-q", "-bytecode-compiler", "no",
            "-profile", str(stage / "kernel-profile.json"),
            "-R", str(direct.checking.STDLIB), "Stdlib", "-Q", str(checkpoints), "",
            "-Q", str(ROOT / "work/mathlib-ndjson/foundation"), "LeanImport",
            "-I", str(direct.checking.IMPORTER / "src"), "-Q", str(stage), "", str(source_path)]
        paths = [worker, chunks.WORKER, Path(plan["export"]), BASE / "environ.profile.ml",
                 HERE / "run.py", HERE / "analyze.py", HERE / "trace.gdb", Path("/usr/bin/gdb"),
                 ROOT / "work/mathlib-ndjson/toolchain.json", direct.checking.IMPORTER / "src/lean_import.cmxs"]
        paths += [checkpoints / (c["module"] + ".vo") for c in ancestors]
        (stage / "invocation.json").write_text(json.dumps({"command": command,
            "inputs": {str(p): chunks.sha(p) for p in paths}, "source": source,
            "diagnostics": {k: v for k, v in env.items() if k.startswith(("ROCQ_DIAGNOSTIC", "ROCQ_PROFILE", "ROCQ_MEASURE", "LEAN_IMPORT"))},
            "baseline": str((BASE / "latest").resolve()), "sample_seconds": 20}, indent=2) + "\n")
        print("Investigation log:", stage / "run.log", flush=True)
        started = time.monotonic()
        state, stop = {}, threading.Event()
        sampler = threading.Thread(target=sample_worker, args=(state, stop), daemon=True)
        sampler.start()
        discarded, target_entries = 0, 0
        last_entry = None
        try:
            with (stage / "run.log").open("x") as log:
                process = subprocess.Popen(command, cwd=stage, env=env, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, text=True, errors="replace", bufsize=1)
                with process:
                    for line in process.stdout:
                        match = re.match(r"\[timeout worker\] pid=(\d+) debugger=(\d+)", line)
                        if match:
                            state.update(pid=int(match[1]), debugger=int(match[2]))
                        if line.startswith("[declare start] " + TARGET + " instance 0 "):
                            state["target"] = True
                        if line.startswith("[declare done] " + TARGET + " instance 0 "):
                            state["target"] = False
                        if line.startswith("[conversion entry]"):
                            if not state.get("target"):
                                discarded += 1
                                continue
                            target_entries += 1
                            last_entry = line
                            if target_entries > 10_000 and target_entries % 1_000:
                                continue
                        log.write(line)
                        log.flush()
                    code = process.wait()
                    if last_entry:
                        (stage / "last-conversion-entry.log").write_text(last_entry)
        finally:
            stop.set()
            sampler.join()
        (stage / "result.json").write_text(json.dumps({"exit_code": code,
            "elapsed_awake_seconds": time.monotonic() - started,
            "prefix_conversion_entries_discarded": discarded,
            "target_conversion_entries": target_entries}, indent=2) + "\n")
        print(summarize(stage), flush=True)


if __name__ == "__main__":
    main()
