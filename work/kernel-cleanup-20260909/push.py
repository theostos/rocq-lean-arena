#!/usr/bin/env python3
"""Publish only the approved kernel cleanup, with recovery tags and exact leases."""
import json
from pathlib import Path
import tempfile

from prepare import WORK, git, index_env

before = json.loads((WORK / "before.json").read_text())
result = json.loads((WORK / "result.json").read_text())
if (WORK / "pushed.json").exists():
    raise SystemExit("Already published; inspect pushed.json before retrying")
assert git("remote", "get-url", "--push", "fork") == "git@github.com:theostos/rocq.git"

# Only the guide changes: replace its pre-publication wording in the same commit.
guide = result["docs"]
guide_ref = "refs/heads/" + guide["branch"]
assert git("rev-parse", guide_ref) == guide["head"]
with tempfile.TemporaryDirectory(prefix="kernel-guide-publish-") as temporary:
    env = index_env(temporary)
    git("read-tree", guide["head"], env=env)
    blob = git("hash-object", "-w", str(WORK / "KERNEL_PATCHES.md"))
    git("update-index", "--add", "--cacheinfo", f"100644,{blob},KERNEL_PATCHES.md", env=env)
    tree = git("write-tree", env=env)
    head = git("commit-tree", tree, "-p", guide["base"],
               input="Document the consolidated kernel review stack\n")
git("update-ref", guide_ref, head, guide["head"])
guide["head"] = head
(WORK / "result.json").write_text(json.dumps(result, indent=2) + "\n")

def remote_refs():
    return {ref: oid for oid, ref in
            (line.split() for line in git("ls-remote", "--refs", "fork").splitlines())}

remote = remote_refs()
updates = {"refs/heads/" + item["branch"]: item["head"]
           for item in [*result["topics"], result["draft"], guide]}
deletions = [ref for ref in result["removed_local_branches"] if ref in remote]
for ref, head in updates.items():
    assert git("rev-parse", ref) == head, f"Local branch changed: {ref}"
    expected = before["refs"].get(ref)
    assert remote.get(ref) in (None, expected, head), f"Unexpected remote update: {ref}"
for ref in deletions:
    assert remote[ref] == before["refs"][ref], f"Remote deletion target changed: {ref}"

archives = {}
for ref in set(result["removed_local_branches"]) | {
        "refs/heads/" + item["branch"] for item in result["topics"]}:
    suffix = ref.removeprefix("refs/heads/")
    oid = before["refs"][ref]
    assert git("rev-parse", before["archive_prefix"] + suffix) == oid
    archives["refs/tags/archive/kernel-cleanup-20260909/" + suffix] = oid
for ref, oid in before["source_snapshots"].items():
    suffix = "sources/" + ref.removeprefix("refs/heads/")
    assert git("rev-parse", before["archive_prefix"] + suffix) == oid
    archives["refs/tags/archive/kernel-cleanup-20260909/" + suffix] = oid
for ref, oid in archives.items():
    assert remote.get(ref) in (None, oid), f"Recovery tag collision: {ref}"

plan = {"updates": updates, "deletions": deletions, "recovery_tags": archives,
        "remote_before": remote}
(WORK / "push-plan.json").write_text(json.dumps(plan, indent=2) + "\n")

def push(changes):
    if not changes:
        return
    leases = [f"--force-with-lease={ref}:{remote.get(ref, '')}" for ref in changes]
    specs = [f"{oid}:{ref}" for ref, oid in changes.items()]
    print(git("-c", "pack.threads=1", "-c", "pack.windowMemory=64m",
              "push", "--atomic", "--porcelain", *leases, "fork", *specs), flush=True)

print(f"Publishing {len(archives)} recovery tags", flush=True)
push({ref: oid for ref, oid in archives.items() if remote.get(ref) != oid})
saved = remote_refs()
assert all(saved.get(ref) == oid for ref, oid in archives.items())
print(f"Publishing {len(updates)} branch heads and removing {len(deletions)} superseded branches", flush=True)
push({**updates, **{ref: "" for ref in deletions}})
after = remote_refs()
assert all(after.get(ref) == oid for ref, oid in updates.items())
assert all(ref not in after for ref in deletions)
assert all(after.get(ref) == oid for ref, oid in archives.items())
affected = updates.keys() | set(deletions) | archives.keys()
assert {ref: oid for ref, oid in remote.items() if ref not in affected} == {
    ref: oid for ref, oid in after.items() if ref not in affected}
plan["verified"] = True
plan["remote_after"] = after
(WORK / "pushed.json").write_text(json.dumps(plan, indent=2) + "\n")
result["pushed"] = True
(WORK / "result.json").write_text(json.dumps(result, indent=2) + "\n")
print("Remote heads, deletions, recovery tags and untouched refs verified.", flush=True)
