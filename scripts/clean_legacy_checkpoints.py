#!/usr/bin/env python3
"""Audit/remove only superseded Cslib*.vo artifacts in two legacy directories."""

import argparse
import json
import os
from pathlib import Path
import stat
import sys

import run_chunked_import as chunks

ROOT = chunks.ROOT
DIRECTORIES = (ROOT / "work/cslib-checkpoints", ROOT / "work/cslib-v2")


def candidates():
    result = []
    for directory in DIRECTORIES:
        if directory.is_symlink():
            raise ValueError("Refusing symlinked checkpoint directory")
        for path in sorted(directory.glob("Cslib*.vo")):
            if path.is_symlink() or not path.is_file() or not path.with_suffix(".v").is_file():
                continue
            info = path.stat()
            result.append({"path": str(path), "bytes": info.st_size, "inode": info.st_ino,
                           "mtime_ns": info.st_mtime_ns, "sha256": chunks.sha(path),
                           "source_sha256": chunks.sha(path.with_suffix(".v"))})
    return result


def in_use(paths):
    system_helpers = []
    uninspectable = []
    for process in Path("/proc").iterdir():
        if not process.name.isdigit() or int(process.name) == os.getpid():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            status = (process / "status").read_text()
            if any(line.startswith("State:") and line.split()[1] == "Z" for line in status.splitlines()):
                # A reaped workload awaiting waitpid has no open descriptors.
                continue
            command = (process / "cmdline").read_bytes().decode(errors="replace")
            if any(str(d) in command for d in DIRECTORIES):
                raise ValueError("A process references a legacy directory: " + process.name)
            for fd in (process / "fd").iterdir():
                try:
                    target = str(fd.resolve(strict=True))
                except (FileNotFoundError, PermissionError):
                    continue
                if target in paths:
                    raise ValueError("An obsolete checkpoint is open: " + target)
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError as exc:
            # systemd's PAM session helper intentionally has root-owned /proc
            # descriptors after dropping UID. It is not a compiler or file job.
            # Verify both its role and parent; all other unreadable jobs refuse.
            status = (process / "status").read_text()
            parent_id = next(line.split()[1] for line in status.splitlines() if line.startswith("PPid:"))
            parent = Path("/proc") / parent_id
            if ((process / "comm").read_text().strip() == "(sd-pam)"
                    and (parent / "comm").read_text().strip() == "systemd"
                    and b"--user" in (parent / "cmdline").read_bytes()):
                system_helpers.append({"pid": int(process.name), "role": "systemd user PAM helper"})
                continue
            role = (process / "comm").read_text().strip()
            credential_agents = {"ssh-agent": b"/usr/bin/ssh-agent", "gpg-agent": b"/usr/bin/gpg-agent"}
            if (role in credential_agents
                    and (process / "cmdline").read_bytes().split(b"\0")[0] == credential_agents[role]):
                # The system credential agent does not read Rocq checkpoints;
                # do not try to inspect its protected credential descriptors.
                system_helpers.append({"pid": int(process.name), "role": "system " + role})
                continue
            uninspectable.append(process.name + " (" + (process / "comm").read_text().strip() + ")")
    if uninspectable:
        raise ValueError("Cannot inspect open files of: " + ", ".join(uninspectable))
    return system_helpers


def remove(manifest):
    record = json.loads(manifest.read_text())
    if record.get("format") != "legacy-checkpoint-cleanup-v1" or record.get("removed"):
        raise ValueError("Invalid or already applied cleanup manifest")
    paths = set()
    for item in record["files"]:
        path = Path(item["path"])
        if path.parent not in DIRECTORIES or not path.name.startswith("Cslib") or path.suffix != ".vo":
            raise ValueError("Outside the explicit cleanup scope: " + str(path))
        paths.add(str(path))
    record["uninspectable_system_helpers"] = in_use(paths)
    for item in record["files"]:
        path = Path(item["path"])
        info = path.lstat()
        if (not stat.S_ISREG(info.st_mode) or info.st_ino != item["inode"] or info.st_mtime_ns != item["mtime_ns"]
                or chunks.sha(path) != item["sha256"] or chunks.sha(path.with_suffix(".v")) != item["source_sha256"]):
            raise ValueError("Candidate changed since audit: " + str(path))
    protected_path = ROOT / "work/cslib-loop/latest/repair-01/protected-inputs.json"
    protected = json.loads(protected_path.read_text()) if protected_path.is_file() else {}
    if paths.intersection(protected):
        raise ValueError("An active repair protects a cleanup candidate")
    record["removed"] = []
    for item in record["files"]:
        Path(item["path"]).unlink()
        record["removed"].append(item["path"])
        chunks.save_json(manifest, record)
    print("Removed %d obsolete compiled checkpoints; %.2f GiB reclaimed. Sources/logs retained." %
          (len(record["removed"]), sum(item["bytes"] for item in record["files"]) / 1024**3))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("audit", "apply"))
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "audit":
            if args.manifest.exists():
                raise ValueError("Refusing to overwrite a cleanup audit")
            files = candidates()
            args.manifest.parent.mkdir(parents=True, exist_ok=True)
            chunks.save_json(args.manifest, {"format": "legacy-checkpoint-cleanup-v1", "files": files})
            print("Candidates: %d; %.2f GiB; audit: %s" %
                  (len(files), sum(f["bytes"] for f in files) / 1024**3, args.manifest))
        else:
            remove(args.manifest)
    except (OSError, ValueError, KeyError) as exc:
        print("Checkpoint cleanup:", exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
