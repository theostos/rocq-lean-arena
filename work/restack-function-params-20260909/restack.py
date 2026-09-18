#!/usr/bin/env python3
"""Restack the local review DAG over the tested function-parameter fix."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
REPO = ROOT / "_worktrees/review/importer-submit-foundations-20260908"
HERE = Path(__file__).resolve().parent
BASE = "a22637a37789cbfaedb6b78e2fa0c733eef1306e"
FIX = "7bb973660d9906af3d76b612a83217e100636fd6"
OWNER = "refs/heads/submit/mutual-inductives"
ARCHIVE = "refs/archive/function-params-20260909/"


def git(*args, cwd=REPO, data=None, env=None):
    return subprocess.check_output(["git", "-C", str(cwd), *args], input=data, env=env)


def revision(ref):
    return git("rev-parse", ref).decode().strip()


def save(name, value):
    (HERE / name).write_text(json.dumps(value, indent=2) + "\n")


def main():
    if (HERE / "before.json").exists():
        raise RuntimeError("Restack already prepared; inspect its saved state")
    assert revision(OWNER) == FIX and revision(FIX + "^") == BASE
    inventory = dict(line.split() for line in git(
        "for-each-ref", "--format=%(refname) %(objectname)",
        "refs/heads", "refs/remotes").decode().splitlines())
    candidates = git("for-each-ref", "--contains=" + BASE,
                     "--format=%(refname)", "refs/heads").decode().splitlines()
    refs = [ref for ref in candidates if ref != OWNER]
    assert all(ref.startswith("refs/heads/submit/") or ref in (
        "refs/heads/integration/importer-review-stock",
        "refs/heads/integration/importer-review-experimental",
        "refs/heads/docs/cslib-patches") for ref in refs)
    old_heads = {ref: inventory[ref] for ref in refs}
    worktrees = {}
    dirty_hashes = {}
    for record in git("worktree", "list", "--porcelain").decode().strip().split("\n\n"):
        fields = dict(line.split(" ", 1) for line in record.splitlines() if " " in line)
        ref = fields.get("branch")
        if ref not in old_heads:
            continue
        path = Path(fields["worktree"])
        status = git("status", "--porcelain=v1", cwd=path).decode()
        if status:
            assert ref == "refs/heads/docs/cslib-patches" and status == " M PR_BODIES.md\n", status
            notes = path / "PR_BODIES.md"
            dirty_hashes[str(notes)] = hashlib.sha256(notes.read_bytes()).hexdigest()
        worktrees[ref] = path
    save("before.json", {"refs": inventory, "fix": FIX, "base": BASE,
                         "affected": old_heads, "dirty_files": dirty_hashes})
    patch = git("diff", "--binary", BASE, FIX, "--", "src/lean.ml")
    assert git("diff", "--numstat", BASE, FIX).decode() == "8\t2\tsrc/lean.ml\n"
    commits = git("rev-list", "--reverse", "--topo-order", "--ancestry-path",
                  *old_heads.values(), "^" + BASE).decode().splitlines()
    mapping = {BASE: FIX}
    with tempfile.TemporaryDirectory(prefix="restack-index-", dir=HERE) as temporary:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / "index"))
        for old in commits:
            git("read-tree", old, env=env)
            git("apply", "--cached", "--check", "-", data=patch, env=env)
            git("apply", "--cached", "--whitespace=error", "-", data=patch, env=env)
            tree = git("write-tree", env=env).decode().strip()
            assert git("diff", "--numstat", old, tree).decode() == "8\t2\tsrc/lean.ml\n"
            parents = git("show", "-s", "--format=%P", old).decode().split()
            new_parents = [mapping.get(parent, parent) for parent in parents]
            assert parents != new_parents
            author = git("show", "-s", "--format=%an%x00%ae%x00%aI", old).decode().strip().split("\0")
            commit_env = dict(env, GIT_AUTHOR_NAME=author[0], GIT_AUTHOR_EMAIL=author[1],
                              GIT_AUTHOR_DATE=author[2])
            message = git("cat-file", "commit", old).split(b"\n\n", 1)[1]
            parent_args = [arg for parent in new_parents for arg in ("-p", parent)]
            new = git("commit-tree", tree, *parent_args, data=message, env=commit_env).decode().strip()
            mapping[old] = new
            print(old[:8], "->", new[:8], flush=True)
    new_heads = {ref: mapping[old] for ref, old in old_heads.items()}
    save("prepared.json", {"old": old_heads, "new": new_heads, "commits": mapping})
    for ref, old in {OWNER: BASE, **old_heads}.items():
        git("update-ref", ARCHIVE + ref.removeprefix("refs/heads/"), old, "0" * 40)
    updated = []
    try:
        for ref, path in worktrees.items():
            git("read-tree", "-m", "-u", old_heads[ref], new_heads[ref], cwd=path)
            updated.append(ref)
        transaction = "start\n" + "".join(
            f"update {ref} {new_heads[ref]} {old_heads[ref]}\n" for ref in refs) + "prepare\ncommit\n"
        git("update-ref", "--stdin", data=transaction.encode())
    except BaseException:
        for ref in reversed(updated):
            git("read-tree", "-m", "-u", new_heads[ref], old_heads[ref], cwd=worktrees[ref])
        raise
    after = dict(line.split() for line in git(
        "for-each-ref", "--format=%(refname) %(objectname)",
        "refs/heads", "refs/remotes").decode().splitlines())
    assert after == {**inventory, **new_heads}
    for ref, new in new_heads.items():
        git("merge-base", "--is-ancestor", FIX, new)
        git("diff", "--check", old_heads[ref], new)
    for ref, path in worktrees.items():
        status = git("status", "--porcelain=v1", cwd=path).decode()
        expected = " M PR_BODIES.md\n" if ref == "refs/heads/docs/cslib-patches" and dirty_hashes else ""
        assert status == expected, (ref, status)
    for path, digest in dirty_hashes.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    save("result.json", {"fix": FIX, "restacked_branches": new_heads, "commits": mapping,
                         "unrelated_refs_unchanged": True, "dirty_files_preserved": True,
                         "published": False, "archive_prefix": ARCHIVE})
    print("Restacked", len(refs), "local branches; no push or build", flush=True)


if __name__ == "__main__":
    main()
