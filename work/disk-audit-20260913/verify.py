#!/usr/bin/env python3
"""Check protected input hashes and account for hard links after cleanup."""
import collections
import csv
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
ACTIVE = ROOT / "work/mathlib-alignment-5m-20260913-with-terminal"


def digest(p):
    with p.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


expected = {}
for p in (ACTIVE / "toolchain.json", ROOT / "work/mathlib-thin-skeleton-repro/resume-approval.json"):
    expected.update(json.loads(p.read_text())["inputs"])
plan = json.loads((ACTIVE / "checkpoints/plan.json").read_text())
expected[plan["export"]] = plan["export_sha256"]
failures = []
for filename, sha in expected.items():
    p = Path(filename)
    if not p.is_file() or digest(p) != sha:
        failures.append(filename)
opener = gzip.open if (OUT / "removed.csv.gz").exists() else open
journal = OUT / ("removed.csv.gz" if opener is gzip.open else "removed.csv")
with opener(journal, "rt") as f:
    deleted = list(csv.DictReader(f))
inodes = collections.defaultdict(list)
for row in deleted:
    inodes[(row["device"], row["inode"])].append(row)
reclaimed = 0
for rows in inodes.values():
    if len(rows) == int(rows[0]["nlink"]):
        reclaimed += max(int(r["allocated_bytes"]) for r in rows)
result = {
    "protected_input_hashes_checked": len(expected),
    "protected_input_failures": failures,
    "reclaimed_regular_file_allocated_bytes": reclaimed,
    "reclaimed_GiB": reclaimed / 1024**3,
    "note": "Reclamation counts only removed inodes whose last hard link was deleted; directories left intact.",
    "repository_allocated_bytes": int(subprocess.check_output(["du", "-sx", "-B1", str(ROOT)]).split()[0]),
    "service": subprocess.check_output(["systemctl", "--user", "show", "rocq-mathlib-alignment-5m-20260913-thin-skeleton.service", "-p", "MainPID", "-p", "ActiveState", "-p", "SubState"]).decode(),
}
(OUT / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
if failures:
    raise SystemExit(1)
