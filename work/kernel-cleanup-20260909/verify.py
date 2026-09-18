#!/usr/bin/env python3
"""Small static checks only; never run or rebuild Rocq."""
import hashlib
import json
from pathlib import Path
import subprocess

from prepare import BASE, REPO, ROOT, WORK, git

compiler = "/home/theo/.opam/rocq93_native/bin/ocamlc"
checkout = ROOT / "_worktrees/review/kernel-clean-20260909"
prepared = json.loads((WORK / "prepared.json").read_text())
before = json.loads((WORK / "before.json").read_text())
head = prepared["topics"][-1]["head"]
assert git("rev-parse", "HEAD", cwd=checkout) == head
snapshot = before["source_snapshots"]["refs/heads/prototype/compact-peano-view"]
production_roots = ["checker", "kernel", "lib", "library", "pretyping", "tactics", "vernac"]
assert not git("diff", snapshot, "--", *production_roots), "Live sources changed"
for topic in prepared["topics"]:
    git("diff", "--check", topic["base"], topic["head"])
    assert not git("diff", "--name-only", BASE, topic["head"], "--", "REVIEW.md", "test-suite")

changed = git("diff", "--name-only", BASE, head).splitlines()
interfaces = subprocess.check_output(
    ["rg", "--files", "--hidden", "--no-ignore", "-g", "*.cmi", str(REPO / "_build/default")],
    text=True).splitlines()
include_dirs = sorted({str(Path(path).parent) for path in interfaces})
include_dirs.append("/home/theo/.opam/rocq93_native/lib/findlib")
includes = [arg for directory in include_dirs for arg in ("-I", directory)]
parsed, typed, unavailable = [], [], {}
for path in changed:
    suffix = Path(path).suffix
    if suffix not in {".ml", ".mli"}:
        continue
    mode = "-intf" if suffix == ".mli" else "-impl"
    command = [compiler, "-stop-after", "parsing", mode, str(checkout / path)]
    subprocess.run(command, check=True, capture_output=True, text=True)
    parsed.append(path)
    if path.startswith("checker/"):
        unavailable[path] = "Standalone checker interfaces are not built (its Values differs from kernel.Values)."
        continue
    if suffix == ".ml":
        command = [compiler, "-stop-after", "typing", "-w", "+a-4-24-40-42-44-50-70",
                   *includes, mode, str(checkout / path)]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            if "Error: Unbound module " not in result.stderr:
                raise RuntimeError(f"Typecheck failed: {path}\n{result.stderr}")
            unavailable[path] = result.stderr
        else:
            typed.append(path)

for path in ("kernel/environ.ml", "kernel/hConstr.ml", "kernel/vars.ml",
             "kernel/cClosure.ml", "kernel/conversion.ml"):
    assert path in typed, f"Cleanup not typechecked: {path}"

manifest = json.loads((ROOT / "work/mathlib-from-start/latest/manifest.json").read_text())
unchanged = {}
for path, expected in manifest["inputs"].items():
    actual = hashlib.file_digest(open(path, "rb"), "sha256").hexdigest()
    assert actual == expected, f"Runtime input changed: {path}"
    unchanged[path] = actual
report = {"head": head, "parsed": parsed, "typed_against_existing_interfaces": typed,
          "unavailable_interfaces": unavailable,
          "runtime_inputs_unchanged": unchanged,
          "live_kernel_sources_unchanged": True, "full_build": "not run",
          "runtime_regressions": "not run while Mathlib is active"}
(WORK / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({"parsed": len(parsed), "typed": len(typed),
                  "unavailable": list(unavailable), "runtime_unchanged": True}))
