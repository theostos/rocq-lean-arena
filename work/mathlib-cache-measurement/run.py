#!/usr/bin/env python3
"""One guarded diagnostic replay; no repairs, restarts or model monitoring."""
import fcntl
from functools import lru_cache
import json
import os
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
from report import summarize


def main():
    with (chunks.OLD_RUN / "launcher.lock").open("r") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        checkpoints = ROOT / "work/mathlib-ndjson/checkpoints"
        plan = json.loads((checkpoints / "plan.json").read_text())
        identity = json.loads((HERE / "worker.json").read_text())
        worker = HERE / "rocqworker.profile.exe"
        chunks.sha = lru_cache(maxsize=None)(chunks.sha)
        if chunks.sha(worker) != identity["sha256"]:
            raise RuntimeError("Diagnostic worker changed")
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
        source, count = re.subn(r'(Lean Import "[^"]+" 9000001 )10000001\.',
                               r'\g<1>9239032.', source)
        if count != 1 or "Set Lean Line Timeout 1800." not in source:
            raise RuntimeError("Unexpected original source")
        source_path = stage / "MathlibTo10000000.v"
        source_path.write_text(source)
        env = direct.environment(16384)
        env.update(ROCQ_MEASURE_DEPENDENCIES="1", LEAN_IMPORT_DECLARE_TRACE_LINE="9239031",
                   LEAN_IMPORT_EXCEPTION_BACKTRACE="1", LEAN_IMPORT_CHECKPOINT_STATS="1")
        if os.environ.get("ROCQ_MEMORY_OWNER_SERVICE"):
            env["ROCQ_MEMORY_OWNER_SERVICE"] = os.environ["ROCQ_MEMORY_OWNER_SERVICE"]
        command = ["bash", str(direct.checking.GUARD), "timeout", "--kill-after=5s", "7200s",
            str(worker), "--kind=compile", "-coqlib", env["COQLIB"], "-q", "-bytecode-compiler", "no",
            "-R", str(direct.checking.STDLIB), "Stdlib", "-Q", str(checkpoints), "",
            "-Q", str(ROOT / "work/mathlib-ndjson/foundation"), "LeanImport",
            "-I", str(direct.checking.IMPORTER / "src"), "-Q", str(stage), "", str(source_path)]
        inputs = {str(p): chunks.sha(p) for p in (worker, Path(plan["export"]),
            HERE / "environ.profile.ml", HERE / "run.py", HERE / "report.py",
            ROOT / "work/mathlib-ndjson/toolchain.json", direct.checking.IMPORTER / "src/lean_import.cmxs")}
        inputs.update({str(checkpoints / (c["module"] + ".vo")):
            chunks.sha(checkpoints / (c["module"] + ".vo")) for c in ancestors})
        (stage / "invocation.json").write_text(json.dumps({"command": command, "inputs": inputs,
            "source": source, "same_module_and_interval_prefix": True,
            "instrumentation": "CPU counters; declaration stages; no debugger or model"}, indent=2) + "\n")
        print("Diagnostic log:", stage / "run.log", flush=True)
        started = time.monotonic()
        with (stage / "run.log").open("x") as log:
            result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        (stage / "result.json").write_text(json.dumps({"exit_code": result.returncode,
            "elapsed_awake_seconds": time.monotonic() - started,
            "vo_saved": source_path.with_suffix(".vo").exists()}, indent=2) + "\n")
        print(summarize(stage), flush=True)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
