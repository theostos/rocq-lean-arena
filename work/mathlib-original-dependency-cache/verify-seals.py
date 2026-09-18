#!/usr/bin/env python3
"""Verify existing seals once per distinct file; never rewrite them."""
import fcntl
from functools import lru_cache
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "scripts"))
import run_chunked_import as chunks

with (chunks.OLD_RUN / "launcher.lock").open("r") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    directory = ROOT / "work/mathlib-ndjson/checkpoints"
    plan = json.loads((directory / "plan.json").read_text())
    chunks.sha = lru_cache(maxsize=None)(chunks.sha)
    chunks.check_entries(chunks.generation_toolchain(plan)["inputs"])
    verified = []
    for chunk in plan["chunks"]:
        if chunk["end"] > 9_000_001:
            break
        migrations = chunks.verify_saved(directory, chunk)
        if migrations is None:
            raise RuntimeError("Missing checkpoint: " + chunk["module"])
        verified.append({"module": chunk["module"], "migrations": migrations})
        print("Verified", chunk["module"], flush=True)
    (HERE / "verified-seals.json").write_text(json.dumps(verified, indent=2) + "\n")
