#!/usr/bin/env python3
"""Preserve the completed attempt separately from the earlier live snapshot."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess

from analyze import ROOT, HERE, parse

destination = HERE / "follow-up"
destination.mkdir(exist_ok=True)
attempt = ROOT / "work/mathlib-ndjson/attempts/20260910T061532993791Z"
paths = [attempt / ("MathlibTo10000000." + suffix + ".log") for suffix in ("run", "guard")]
paths += [ROOT / "work/mathlib-ndjson" / name for name in ("progress.json", "result.json")]
manifest, records = [], []
for path in paths:
    saved = destination / path.name
    if not saved.exists():
        saved.write_bytes(path.read_bytes())
    content = saved.read_bytes()
    manifest.append({"source": str(path.relative_to(ROOT)), "snapshot": saved.name,
                     "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()})
    if path.suffix == ".log":
        records.append(parse(path, content.decode(errors="replace")))
journal = destination / "suspend.log"
if not journal.exists():
    result = subprocess.run(["journalctl", "-u", "systemd-suspend.service", "--since",
        "2026-09-10 09:10:00", "--until", "2026-09-10 09:46:00", "--no-pager"],
        check=True, capture_output=True)
    journal.write_bytes(result.stdout)
manifest.append({"snapshot": journal.name, "sha256": hashlib.sha256(journal.read_bytes()).hexdigest()})
(destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
(destination / "analysis.json").write_text(json.dumps(records, indent=2) + "\n")
stamp = destination / "captured-at.txt"
if not stamp.exists():
    stamp.write_text(datetime.now(timezone.utc).isoformat() + "\n")
print("Completed-failure evidence:", destination)
