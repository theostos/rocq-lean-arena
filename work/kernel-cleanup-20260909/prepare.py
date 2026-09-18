#!/usr/bin/env python3
"""Archive source states and assemble kernel review topics without a rebuild."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
WORK = Path(__file__).resolve().parent
REPO = ROOT / "_worktrees/rocq/compact-peano-view"
PREFIX = "refs/archive/kernel-cleanup-20260909/"
BASE = "f756383de2e66f63c95815c73838596d7d97c1c2"


def git(*args, cwd=REPO, env=None, input=None):
    return subprocess.check_output(
        ["git", *args], cwd=cwd, env=env, input=input, text=True).strip()


def worktrees():
    return [dict(line.split(" ", 1) if " " in line else (line, "")
                 for line in block.splitlines())
            for block in git("worktree", "list", "--porcelain").split("\n\n")]


def index_env(directory):
    return dict(os.environ, GIT_INDEX_FILE=str(Path(directory) / "index"))


def snapshot_tree(path, parent, include_tests=False):
    with tempfile.TemporaryDirectory(prefix="kernel-snapshot-") as temporary:
        env = index_env(temporary)
        git("read-tree", parent, cwd=path, env=env)
        git("add", "-u", cwd=path, env=env)
        if include_tests:
            sources = git("ls-files", "--others", "--exclude-standard",
                          "test-suite", cwd=path).splitlines()
            sources = [p for p in sources
                       if Path(p).suffix in {".ml", ".mli", ".v"}
                       or Path(p).name == "dune"]
            if sources:
                git("add", "--", *sources, cwd=path, env=env)
        tree = git("write-tree", cwd=path, env=env)
        return git("commit-tree", tree, "-p", parent,
                   input="Preserve kernel source before review cleanup\n")


def archive():
    destination = WORK / "before.json"
    if destination.exists():
        raise SystemExit("Archive already exists; refusing to overwrite it")
    refs = dict(line.split(" ", 1) for line in git(
        "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads").splitlines())
    states = worktrees()
    snapshots = {}
    for state in states:
        branch = state.get("branch", "")
        if branch.startswith(("refs/heads/diagnostic/", "refs/heads/experiment/")) \
                or branch == "refs/heads/prototype/compact-peano-view":
            path = Path(state["worktree"])
            state["status"] = git("status", "--short", cwd=path)
            snapshots[branch] = snapshot_tree(
                path, state["HEAD"], include_tests=path == REPO)
    commands = ["start"]
    for ref, oid in refs.items():
        commands.append(f"create {PREFIX}{ref.removeprefix('refs/heads/')} {oid}")
    for ref, oid in snapshots.items():
        commands.append(f"create {PREFIX}sources/{ref.removeprefix('refs/heads/')} {oid}")
    commands += ["prepare", "commit"]
    git("update-ref", "--stdin", input="\n".join(commands) + "\n")
    destination.write_text(json.dumps({
        "base": BASE, "refs": refs, "worktrees": states,
        "source_snapshots": snapshots, "archive_prefix": PREFIX,
    }, indent=2) + "\n")
    print(json.dumps({"archive": str(destination), "source_snapshots": snapshots}))


TOPICS = [
    ("dependency-cache", "Bound dependency-query storage"),
    ("term-sharing", "Preserve DAG sharing during kernel term traversals"),
    ("reduction-registrations", "Validate and persist reduction registrations"),
    ("compact-peano", "Evaluate registered Peano arithmetic using compact closures"),
    ("unit-eta", "Support conversion for registered unit-like inductives"),
    ("conversion-strategies", "Guide conversion through dependencies and projections"),
]


def source_paths(parent, head):
    return [p for p in git("diff", "--name-only", parent, head).splitlines()
            if p != "REVIEW.md" and not p.startswith("test-suite/")]


def build():
    before = json.loads((WORK / "before.json").read_text())
    refs = before["refs"]
    commits = []
    parent = BASE
    old_parent = BASE
    with tempfile.TemporaryDirectory(prefix="kernel-review-") as temporary:
        env = index_env(temporary)
        for topic, title in TOPICS:
            branch = "review/" + topic
            old = refs["refs/heads/" + branch]
            git("read-tree", parent, env=env)
            for path in source_paths(old_parent, old):
                mode, _, blob = git("ls-tree", old, "--", path).split()[:3]
                candidate = WORK / "core" / path
                if topic == "compact-peano" and path == "kernel/cClosure.ml" \
                        and not candidate.exists():
                    raise RuntimeError("Missing cleaned closure source")
                if path == "kernel/conversion.ml":
                    variant = {"compact-peano": "compact", "unit-eta": "unit",
                               "conversion-strategies": "final"}[topic]
                    candidate = WORK / "conversion" / f"conversion-{variant}.ml"
                    if not candidate.exists():
                        raise RuntimeError(f"Missing {candidate}")
                if candidate.exists():
                    blob = git("hash-object", "-w", str(candidate))
                git("update-index", "--add", "--cacheinfo", f"{mode},{blob},{path}", env=env)
            tree = git("write-tree", env=env)
            head = git("commit-tree", tree, "-p", parent, input=title + "\n")
            git("diff", "--check", parent, head)
            commits.append({"branch": branch, "head": head, "base": parent,
                            "old_head": old, "title": title,
                            "stat": git("diff", "--stat", parent, head)})
            parent, old_parent = head, old

        # Keep the ABI-changing Zarith/flag proposal off the checked stack.
        draft_old = refs["refs/heads/review/binary-peano"]
        draft_old_parent = refs["refs/heads/review/reduction-registrations"]
        draft_parent = commits[2]["head"]
        git("read-tree", draft_parent, env=env)
        patch = subprocess.check_output(
            ["git", "diff", "--binary", draft_old_parent, draft_old, "--",
             *source_paths(draft_old_parent, draft_old)], cwd=REPO, text=True)
        git("apply", "--cached", "--whitespace=error", env=env, input=patch)
        draft_tree = git("write-tree", env=env)
        draft = git("commit-tree", draft_tree, "-p", draft_parent,
                    input="Draft: evaluate Peano arithmetic with Zarith and an opt-in flag\n")
    payload = {"topics": commits, "draft": {
        "branch": "draft/binary-peano-zarith", "head": draft,
        "base": draft_parent, "old_head": draft_old,
        "status": "Untested; not used for the cslib import"}}
    (WORK / "prepared.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))


def install():
    before = json.loads((WORK / "before.json").read_text())
    prepared = json.loads((WORK / "prepared.json").read_text())
    refs = before["refs"]
    obsolete = [ref for ref in refs if ref.startswith((
        "refs/heads/fix/", "refs/heads/experiment/", "refs/heads/diagnostic/"))]
    obsolete += ["refs/heads/review/kernel-diagnostics",
                 "refs/heads/review/kernel-diagnostics-current",
                 "refs/heads/review/binary-peano"]
    updated = {"refs/heads/" + topic["branch"]: topic["head"]
               for topic in prepared["topics"]}
    affected = set(obsolete) | updated.keys()
    # Detach using symbolic HEAD only: preserve every index, source and build.
    detached = []
    for state in worktrees():
        if state.get("branch") in affected:
            ref = state["branch"]
            if state["HEAD"] != refs[ref]:
                raise RuntimeError(f"Worktree moved since archive: {state}")
            git("update-ref", "--no-deref", "HEAD", state["HEAD"], cwd=state["worktree"])
            detached.append(state["worktree"])
    commands = ["start"]
    for ref, head in updated.items():
        commands.append(f"update {ref} {head} {refs[ref]}")
    for ref in obsolete:
        commands.append(f"delete {ref} {refs[ref]}")
    draft = prepared["draft"]
    commands.append(f"create refs/heads/{draft['branch']} {draft['head']}")
    guide = prepared["docs"]
    commands.append(f"create refs/heads/{guide['branch']} {guide['head']}")
    commands += ["prepare", "commit"]
    try:
        git("update-ref", "--stdin", input="\n".join(commands) + "\n")
    except Exception:
        for state in before["worktrees"]:
            if state["worktree"] in detached:
                git("symbolic-ref", "HEAD", state["branch"], cwd=state["worktree"])
        raise
    prepared["removed_local_branches"] = obsolete
    prepared["detached_preserved_worktrees"] = detached
    prepared["pushed"] = False
    (WORK / "result.json").write_text(json.dumps(prepared, indent=2) + "\n")
    print(json.dumps({"updated": updated, "removed": obsolete, "pushed": False}, indent=2))


def docs():
    prepared = json.loads((WORK / "prepared.json").read_text())
    validation = json.loads((WORK / "validation.json").read_text())
    parent = prepared["topics"][-1]["head"]
    assert validation["head"] == parent
    with tempfile.TemporaryDirectory(prefix="kernel-guide-") as temporary:
        env = index_env(temporary)
        git("read-tree", parent, env=env)
        blob = git("hash-object", "-w", str(WORK / "KERNEL_PATCHES.md"))
        git("update-index", "--add", "--cacheinfo",
            f"100644,{blob},KERNEL_PATCHES.md", env=env)
        tree = git("write-tree", env=env)
        head = git("commit-tree", tree, "-p", parent,
                   input="Document the consolidated kernel review stack\n")
    prepared["docs"] = {"branch": "docs/kernel-patches", "head": head, "base": parent}
    (WORK / "prepared.json").write_text(json.dumps(prepared, indent=2) + "\n")
    print(json.dumps(prepared["docs"]))


if __name__ == "__main__":
    {"archive": archive, "build": build, "docs": docs, "install": install}[sys.argv[1] if len(sys.argv) > 1 else "archive"]()
