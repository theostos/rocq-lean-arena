#!/usr/bin/env python3
"""Apply the reviewed file inventory, never directory-wide deletion.

The user authorized inactive-artifact cleanup after reviewing README.md.
Preserve tracked/untracked checkout sources, current run and validation inputs,
open/mapped files, all links and files changed since the original inventory.
"""
import argparse
import collections
import csv
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time

from audit import ROOT, OUT, ACTIVE, PROTECTED

CATEGORIES = {"git-temporary", "interrupted-export", "obsolete-checkpoint",
              "compiled-artifact", "build-cache", "derived-index",
              "historical-log", "export-review"}
SOURCE_EXTENSIONS = {".ml", ".mli", ".mlg", ".mll", ".mly", ".v", ".lean",
                     ".c", ".h", ".cpp", ".hpp", ".cc", ".S", ".sh", ".py",
                     ".rs", ".md", ".rst", ".patch", ".diff", ".toml", ".yaml", ".yml"}
INVENTORY = OUT / "candidates.csv.gz"
FIELDS = ["category", "allocated_bytes", "size_bytes", "path", "inode", "device", "mtime_ns", "nlink"]


def save(name, obj):
    (OUT / name).write_text(json.dumps(obj, indent=2) + "\n")


def digest(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def git(repo, *args):
    return subprocess.check_output(["git", "--no-optional-locks", "-C", str(repo), *args], stderr=subprocess.DEVNULL)


def protections():
    paths = set()
    inodes = set()
    prefixes = list(PROTECTED)
    snapshots = []
    repo_records = json.loads((OUT / "repositories.json").read_text())
    for rec in repo_records:
        repo = (ROOT / rec["path"]).resolve()
        if not repo.is_relative_to(ROOT):
            raise ValueError("Repo outside scope: " + str(repo))
        if "error" in rec:
            prefixes.append(str(repo.relative_to(ROOT)) + "/")
            continue
        prefix = str(repo.relative_to(ROOT))
        prefix = "" if prefix == "." else prefix + "/"
        files = git(repo, "ls-files", "-z").split(b"\0")
        paths.update(prefix + os.fsdecode(f) for f in files if f)
        # Root has untracked work/ outputs; in actual nested checkouts, preserve
        # all non-ignored untracked files, including handwritten NDJSON tests.
        if repo != ROOT:
            others = git(repo, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
            paths.update(prefix + os.fsdecode(f) for f in others if f)
        changed = set(git(repo, "diff", "--name-only", "-z").split(b"\0"))
        changed.update(git(repo, "diff", "--cached", "--name-only", "-z").split(b"\0"))
        hashes = {}
        for f in changed:
            if f:
                p = repo / os.fsdecode(f)
                if p.is_file() and not p.is_symlink():
                    hashes[str(p)] = digest(p)
        snapshots.append({"path": str(repo), "head": git(repo, "rev-parse", "HEAD").decode().strip(),
                          "dirty_tracked_sha256": hashes})

    def protect(p):
        p = Path(p)
        if p.is_absolute() and p.is_relative_to(ROOT):
            paths.add(str(p.relative_to(ROOT)))
            resolved = p.resolve()
            if resolved.is_relative_to(ROOT):
                paths.add(str(resolved.relative_to(ROOT)))
            try:
                info = p.stat()
                inodes.add((info.st_dev, info.st_ino))
            except FileNotFoundError:
                pass

    def collect(value):
        if isinstance(value, dict):
            for k, v in value.items():
                collect(k)
                collect(v)
        elif isinstance(value, list):
            for v in value:
                collect(v)
        elif isinstance(value, str) and value.startswith(str(ROOT) + "/"):
            protect(value)

    for rel in (ACTIVE + "/toolchain.json", ACTIVE + "/checkpoints/plan.json",
                "work/mathlib-thin-skeleton-repro/resume-approval.json",
                "work/kernel-alignment-pass/final-gates-21/passed.json"):
        collect(json.loads((ROOT / rel).read_text()))
    for seal in (ROOT / ACTIVE / "checkpoints").glob("*.seal/inputs.sha256"):
        for line in seal.read_text().splitlines():
            if len(line) > 66:
                protect(line[66:])
    return paths, inodes, tuple(prefixes), snapshots


def processes():
    paths, inodes, directories = set(), set(), set()
    evidence, unreadable, git_writers = [], [], []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            comm = (proc / "comm").read_text().strip()
            argv = (proc / "cmdline").read_bytes().split(b"\0")
            if not any(argv):
                continue
            if comm.startswith("git") and any(a in argv for a in (b"gc", b"repack", b"pack-objects", b"index-pack", b"prune")):
                git_writers.append(int(proc.name))
            for arg in argv:
                text = os.fsdecode(arg)
                if text.startswith(str(ROOT) + "/"):
                    p = Path(text).resolve()
                    if p.is_dir():
                        directories.add(str(p.relative_to(ROOT)) + "/")
                    elif p.is_file():
                        paths.add(str(p.relative_to(ROOT)))
            for link in [proc / "exe", *list((proc / "fd").iterdir())]:
                try:
                    target = link.resolve(strict=True)
                    info = link.stat()
                    if target.is_relative_to(ROOT):
                        paths.add(str(target.relative_to(ROOT)))
                        inodes.add((info.st_dev, info.st_ino))
                        evidence.append({"pid": int(proc.name), "path": str(target.relative_to(ROOT)), "role": comm})
                except (OSError, RuntimeError):
                    continue
            try:
                for line in (proc / "maps").read_text().splitlines():
                    fields = line.split(None, 5)
                    if len(fields) == 6 and fields[5].startswith(str(ROOT) + "/"):
                        target = Path(fields[5])
                        paths.add(str(target.relative_to(ROOT)))
                        try:
                            info = target.stat()
                            inodes.add((info.st_dev, info.st_ino))
                        except OSError:
                            pass
            except PermissionError:
                pass
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            unreadable.append({"pid": int(proc.name), "role": comm})
    # Known desktop credential/PAM helpers do not run builds or read this repo.
    unknown = [p for p in unreadable if p["role"] not in {"(sd-pam)", "ssh-agent", "gpg-agent"}]
    if unknown:
        raise ValueError("Cannot inspect potentially relevant processes: " + repr(unknown))
    if git_writers:
        raise ValueError("Git pack writer active; retry after it finishes: " + repr(git_writers))
    return paths, inodes, tuple(directories), {"open_paths": evidence, "unreadable_helpers": unreadable}


def unchanged(row):
    rel = row["path"]
    p = ROOT / rel
    if Path(rel).is_absolute() or ".." in Path(rel).parts or p.resolve() != p:
        return False
    try:
        s = p.lstat()
    except FileNotFoundError:
        return False
    return (stat.S_ISREG(s.st_mode) and s.st_ino == int(row["inode"])
            and s.st_dev == int(row["device"]) and s.st_size == int(row["size_bytes"])
            and s.st_mtime_ns == int(row["mtime_ns"]) and s.st_nlink == int(row["nlink"]))


def select(rows, protected, pinned_inodes, prefixes, open_paths, open_inodes, active_dirs):
    chosen, skipped = [], []
    for row in rows:
        name = row["path"]
        p = Path(name)
        reason = None
        if row["category"] not in CATEGORIES:
            raise ValueError("Unexpected category: " + str(row))
        if name.startswith(prefixes) or name in protected:
            reason = "protected-input-or-checkout-file"
        elif name in open_paths or name.startswith(active_dirs) or (int(row["device"]), int(row["inode"])) in (pinned_inodes | open_inodes):
            reason = "active-process-reference"
        elif p.suffix in SOURCE_EXTENSIONS:
            reason = "source-like-file-preserved"
        elif row["category"] == "export-review" and int(row["size_bytes"]) < 16 * 1024**2:
            reason = "small-regression-input-preserved"
        elif "dumps" in p.parts and row["category"] in {"historical-log", "export-review"}:
            reason = "fixture-preserved"
        elif row["category"] == "git-temporary" and not re.fullmatch(r"\.git/objects/(pack/tmp_pack_[^/]+|[0-9a-f]{2}/tmp_obj_[^/]+)", name):
            raise ValueError("Invalid Git temporary target: " + name)
        elif ".git" in p.parts and row["category"] != "git-temporary":
            raise ValueError("Refusing Git metadata: " + name)
        elif not unchanged(row):
            reason = "changed-missing-or-linked-since-audit"
        if reason:
            skipped.append({**row, "reason": reason})
        else:
            chosen.append(row)
    return chosen, skipped


def totals(rows):
    result = collections.defaultdict(lambda: {"files": 0, "allocated_bytes": 0})
    for row in rows:
        result[row["category"]]["files"] += 1
        result[row["category"]]["allocated_bytes"] += int(row["allocated_bytes"])
    return dict(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("prepare", "apply"))
    args = parser.parse_args()
    if any((OUT / name).exists() for name in ("removed.csv", "removed.csv.gz", "cleanup-result.json")):
        raise ValueError("Cleanup journal already exists; inspect it instead of rerunning")
    with gzip.open(INVENTORY, "rt") as f:
        rows = list(csv.DictReader(f))
    if len({r["path"] for r in rows}) != len(rows):
        raise ValueError("Duplicate inventory paths")
    protected, pinned_inodes, prefixes, snapshots = protections()
    open_paths, open_inodes, active_dirs, process_evidence = processes()
    selected, skipped = select(rows, protected, pinned_inodes, prefixes, open_paths, open_inodes, active_dirs)
    summary = {"time": time.time(), "mode": args.mode, "inventory_sha256": digest(INVENTORY),
               "selected": totals(selected), "skipped": totals(skipped),
               "selected_files": len(selected), "selected_allocated_bytes": sum(int(r["allocated_bytes"]) for r in selected)}
    if args.mode == "prepare":
        for name, records in (("approved-candidates.csv.gz", selected), ("skipped.csv.gz", skipped)):
            with gzip.open(OUT / name, "wt") as f:
                writer = csv.DictWriter(f, fieldnames=FIELDS + (["reason"] if name.startswith("skipped") else []))
                writer.writeheader()
                writer.writerows(records)
        save("cleanup-plan.json", summary)
        save("source-snapshots.json", snapshots)
        save("process-protection.json", process_evidence)
        print(json.dumps(summary, indent=2), flush=True)
        return
    prepared = json.loads((OUT / "cleanup-plan.json").read_text())
    if prepared["inventory_sha256"] != summary["inventory_sha256"]:
        raise ValueError("Inventory changed")
    with gzip.open(OUT / "approved-candidates.csv.gz", "rt") as f:
        approved = {r["path"] for r in csv.DictReader(f)}
    selected = [r for r in selected if r["path"] in approved]
    removed, last_check = [], time.monotonic()
    with (OUT / "removed.csv").open("x") as log:
        writer = csv.DictWriter(log, fieldnames=FIELDS)
        writer.writeheader()
        for row in selected:
            if time.monotonic() - last_check > 15:
                open_paths, open_inodes, active_dirs, _ = processes()
                last_check = time.monotonic()
            name = row["path"]
            if (name in open_paths or name.startswith(active_dirs)
                    or (int(row["device"]), int(row["inode"])) in open_inodes
                    or not unchanged(row)):
                continue
            # A manifest-resolved, revalidated, individual regular file only.
            # No recursive directory removal or symbolic-link traversal.
            (ROOT / name).unlink()
            writer.writerow(row)
            removed.append(row)
            if len(removed) % 1000 == 0:
                log.flush()
            if len(removed) % 20000 == 0:
                print(json.dumps({"removed_files": len(removed), "allocated_GiB": sum(int(r["allocated_bytes"]) for r in removed) / 1024**3}), flush=True)
    mismatches = []
    for repo in snapshots:
        for p, expected in repo["dirty_tracked_sha256"].items():
            if not Path(p).is_file() or digest(Path(p)) != expected:
                mismatches.append(p)
    result = {"finished": time.time(), "removed_files": len(removed), "removed": totals(removed),
              "allocated_bytes_from_audit": sum(int(r["allocated_bytes"]) for r in removed),
              "dirty_tracked_source_mismatches": mismatches,
              "recovery": "No trash copy. Rebuild/re-export generated files from preserved sources; removed historical logs and incomplete temporary files are not recoverable from this journal.",
              "protected": prefixes, "worktrees_removed": 0}
    save("cleanup-result.json", result)
    print(json.dumps(result, indent=2), flush=True)
    if mismatches:
        raise ValueError("Source snapshot changed during cleanup; review mismatches")


if __name__ == "__main__":
    main()
