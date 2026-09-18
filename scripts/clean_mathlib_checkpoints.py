#!/usr/bin/env python3
"""Explicit, audited removal of compiled snapshots of the Mathlib export.

Sources, export data, logs, seals and unrelated regression/CSLib artifacts stay.
This deliberately retires old generations; their saved manifests are history,
not resumable chains after removal.
"""
import argparse
import json
import os
from pathlib import Path
import stat
import subprocess

import run_chunked_import as chunks

WORK = chunks.ROOT / "work"
MARKERS = ("mathlib.ndjson", "Mathlib.lean-export")


def idle():
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            if (proc / "comm").read_text().strip() in (
                    "rocqworker", "rocqworker.exe", "rocqchk", "rocqchk.exe"):
                raise ValueError("A Rocq worker/checker is active: " + proc.name)
        except (FileNotFoundError, ProcessLookupError):
            continue


def inspect(path):
    if (not path.is_absolute() or not path.is_relative_to(WORK)
            or path.resolve(strict=True) != path or path.suffix not in (".vo", ".vos", ".vok")):
        raise ValueError("Outside regular Mathlib checkpoint scope: " + str(path))
    info = path.lstat()
    source = path.with_suffix(".v")
    if (not stat.S_ISREG(info.st_mode) or source.is_symlink()
            or not any(marker in source.read_text() for marker in MARKERS)):
        raise ValueError("Not a compiled Mathlib export snapshot: " + str(path))
    return {"path": str(path), "bytes": info.st_size, "inode": info.st_ino,
            "mtime_ns": info.st_mtime_ns, "sha256": chunks.sha(path),
            "source_sha256": chunks.sha(source)}


def audit(manifest):
    if manifest.exists():
        raise ValueError("Refusing to overwrite an audit")
    idle()
    command = ["rg", "-l", "-0", "--hidden", "--no-ignore", "-F",
               "-e", MARKERS[0], "-e", MARKERS[1], "-g", "*.v", str(WORK)]
    found = subprocess.run(command, stdout=subprocess.PIPE, check=True).stdout
    paths = set()
    for name in found.split(b"\0"):
        if not name:
            continue
        source = Path(os.fsdecode(name))
        if source.resolve(strict=True) != source:
            continue
        for suffix in (".vo", ".vos", ".vok"):
            path = source.with_suffix(suffix)
            if path.exists():
                paths.add(path)
    files = [inspect(path) for path in sorted(paths)]
    chunks.save_json(manifest, {"format": "mathlib-snapshot-cleanup-v1", "files": files,
                              "bytes": sum(item["bytes"] for item in files), "removed": []})
    print(json.dumps({"files": len(files), "bytes": sum(item["bytes"] for item in files),
                      "manifest": str(manifest)}))


def remove(manifest):
    record = json.loads(manifest.read_text())
    if record.get("format") != "mathlib-snapshot-cleanup-v1" or record.get("removed"):
        raise ValueError("Invalid or already applied audit")
    idle()
    paths = [item["path"] for item in record["files"]]
    if len(paths) != len(set(paths)):
        raise ValueError("Duplicate cleanup targets")
    for item in record["files"]:
        if inspect(Path(item["path"])) != item:
            raise ValueError("Checkpoint/source changed since audit: " + item["path"])
    idle()
    for item in record["files"]:
        Path(item["path"]).unlink()
        record["removed"].append(item["path"])
        chunks.save_json(manifest, record)
    print(json.dumps({"removed": len(record["removed"]), "bytes": record["bytes"],
                      "recoverable": "Rebuild from retained source/export; no trash copy"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("audit", "apply"))
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    (audit if args.command == "audit" else remove)(args.manifest.resolve())
