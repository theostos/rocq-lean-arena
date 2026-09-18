#!/usr/bin/env python3
"""Read-only repository audit; writes reports only in this script's directory."""
import collections
import csv
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
ACTIVE = "work/mathlib-alignment-5m-20260913-with-terminal"
PROTECTED = (
    ACTIVE + "/",
    "work/kernel-alignment-pass/importer.lFy9zJVL/",
    "_worktrees/rocq/compact-peano-view/",
    "_worktrees/rocq/stdlib-int32-repro/",
    "work/kernel-alignment-pass/final-gates-21/",
    "work/mathlib-thin-skeleton-repro/",
    "_deps/lean-kernel-arena/_build/tests/mathlib.ndjson",
)
REASONS = {
    "git-temporary": "Git temporary object/pack; verify no Git writer/open descriptor before removal.",
    "interrupted-export": "Incomplete export from July; verify idle before deletion.",
    "obsolete-checkpoint": "Compiled import/checkpoint; deleting retires old resume chain; source/log/seal retained.",
    "compiled-artifact": "Rebuildable binary/object/proof outside protected active paths; rebuild before reuse.",
    "build-cache": "Inactive compiler cache/build tree; rebuild/download before reuse; not source checkouts.",
    "derived-index": "Derived experimental import index; regenerate before distributed import.",
    "historical-log": "Historical execution log; optional, loses diagnostic evidence.",
    "export-review": "Completed generated export; retain if still needed by regression/CSLib workflows, or regenerate.",
    "keep-active": "Active Mathlib inputs/checkpoints or latest validation evidence; do not delete during run.",
    "keep-git": "Git history/metadata; never manually delete objects or packs.",
    "keep-source": "Tracked file, source, fixture, manifest, or unclassified data; not blanket-cleanup safe.",
}


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.DEVNULL)


def main():
    raw = subprocess.check_output(["rg", "--files", "--hidden", "--no-ignore", "-0"], cwd=ROOT)
    names = [os.fsdecode(n) for n in raw.split(b"\0") if n]
    repos = {ROOT}
    for name in names:
        if name.endswith("/.git"):
            repos.add((ROOT / name).parent)
        elif name.endswith("/.git/HEAD"):
            repos.add((ROOT / name).parent.parent)
    tracked = set()
    repo_rows = []
    for repo in sorted(repos):
        try:
            files = git(repo, "ls-files", "-z").split(b"\0")
            prefix = str(repo.relative_to(ROOT))
            prefix = "" if prefix == "." else prefix + "/"
            tracked.update(prefix + os.fsdecode(f) for f in files if f)
            status = git(repo, "status", "--porcelain=v1", "--untracked-files=all").decode(errors="replace")
            repo_rows.append({"path": prefix.rstrip("/"), "head": git(repo, "rev-parse", "HEAD").decode().strip(),
                              "status": status, "clean": not status})
        except subprocess.CalledProcessError:
            repo_rows.append({"path": str(repo), "error": "git inventory failed; preserve"})
    pinned = json.loads((ROOT / ACTIVE / "toolchain.json").read_text())["inputs"]
    pinned = {str(Path(p).relative_to(ROOT)) for p in pinned if Path(p).is_relative_to(ROOT)}
    groups = collections.defaultdict(lambda: [0, 0, 0])
    locations = collections.defaultdict(lambda: [0, 0])
    seen = set()
    rows = []
    for name in sorted(names):
        if name.startswith("work/disk-audit-20260913/"):
            continue
        p = ROOT / name
        try:
            s = p.lstat()
        except FileNotFoundError:
            continue
        if not stat.S_ISREG(s.st_mode):
            continue
        inode = (s.st_dev, s.st_ino)
        allocated = s.st_blocks * 512 if inode not in seen else 0
        seen.add(inode)
        category = "keep-source"
        if name in pinned or name.startswith(PROTECTED):
            category = "keep-active"
        elif re.fullmatch(r"\.git/objects/(pack/tmp_pack_[^/]+|[0-9a-f]{2}/tmp_obj_[^/]+)", name):
            category = "git-temporary"
        elif ".git" in p.relative_to(ROOT).parts:
            category = "keep-git"
        elif name in tracked:
            category = "keep-source"
        elif re.fullmatch(r"_deps/lean-kernel-arena/_build/tests/[^/]+\.lean-export\.tmp\.\d+", name):
            category = "interrupted-export"
        elif "/.lake/build/" in name or name.startswith("_build/") or re.match(r"_worktrees/[^/]+/[^/]+/(_build|build)/", name):
            category = "build-cache"
        elif name.startswith("work/distributed-import-implementation-20260909/full-index/"):
            category = "derived-index"
        elif p.suffix in (".vo", ".vos", ".vok") and name.startswith("work/"):
            source = p.with_suffix(".v")
            if source.is_file() and source.stat().st_size < 1024 * 1024:
                body = source.read_text(errors="replace")
                category = ("obsolete-checkpoint" if any(m in body for m in ("mathlib.ndjson", "Mathlib.lean-export", "cslib.ndjson", "Cslib.lean-export"))
                            or re.match(r"(?:Mathlib|Cslib).*?(?:To\d+|Reload)", p.name) else "compiled-artifact")
            else:
                category = "compiled-artifact"
        elif p.suffix in (".o", ".a", ".so", ".exe", ".cmi", ".cmx", ".cmo", ".cma", ".cmxa", ".cmxs", ".vo", ".vos", ".vok", ".glob", ".aux", ".pyc", ".olean", ".ilean"):
            category = "compiled-artifact"
        elif p.suffix in (".ndjson", ".lean-export"):
            category = "export-review"
        elif p.suffix == ".log" or p.name.endswith(".log.out") or (p.suffix == ".out" and name.startswith("work/")):
            category = "historical-log"
        groups[category][0] += 1
        groups[category][1] += allocated
        groups[category][2] += s.st_size
        depth = 3 if name.startswith("_worktrees/") else 2
        loc = "/".join(name.split("/")[:depth])
        locations[(category, loc)][0] += 1
        locations[(category, loc)][1] += allocated
        rows.append({"category": category, "allocated_bytes": allocated, "size_bytes": s.st_size,
                     "path": name, "inode": s.st_ino, "device": s.st_dev, "mtime_ns": s.st_mtime_ns,
                     "nlink": s.st_nlink})
    with (OUT / "files.csv").open("w") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    with (OUT / "candidates.csv").open("w") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(sorted((r for r in rows if not r["category"].startswith("keep-")), key=lambda r: -r["allocated_bytes"]))
    with (OUT / "groups.csv").open("w") as f:
        writer = csv.writer(f)
        writer.writerow(["category", "location", "files", "allocated_bytes"])
        writer.writerows((c, p, *v) for (c, p), v in sorted(locations.items(), key=lambda kv: -kv[1][1]))
    (OUT / "repositories.json").write_text(json.dumps(repo_rows, indent=2) + "\n")
    summary = {"timestamp": time.time(), "root": str(ROOT), "protected_prefixes": PROTECTED,
               "reasons": REASONS, "groups": dict(groups), "regular_files": len(rows),
               "note": "No files deleted. Allocated bytes count hard-linked inodes only once; symlinks not followed; live run can grow. Worktree deletion is a separate, overlapping option, not included in candidate totals."}
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    print("Repositories:", len(repo_rows), "clean:", sum(r.get("clean", False) for r in repo_rows))


if __name__ == "__main__":
    main()
