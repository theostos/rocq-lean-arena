#!/usr/bin/env python3
"""Export the cached, pinned Mathlib without rebuilding or changing its checkout."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

import run_chunked_import as chunks
import checkpoint_generation as generations

ROOT = chunks.ROOT
SOURCE = ROOT / "_deps/lean-kernel-arena/_build/tests/work/cslib/src"
REVISION = "32d24245c7a12ded17325299fd41d412022cd3fe"
TOOLCHAIN = "leanprover/lean4:v4.27.0-rc1"
LEAN = Path("/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1")
EXPORTER = ROOT / "_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export"
CONVERTER = ROOT / "_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py"
OUTPUT = ROOT / "work/library-exports/mathlib-4.27"
CHECKPOINTS = ROOT / "work/library-checkpoints/mathlib"
PLAN = CHECKPOINTS / "full/plan.json"
SMOKE_PLAN = CHECKPOINTS / "mathlib-smoke/plan.json"
SMOKE_MODULE = "Mathlib.Logic.Nontrivial.Defs"
SMOKE_DECLARATION = "nontrivial_iff"
GIB = 1024**3


def inspect_source():
    manifest_path = SOURCE / "lake-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if (SOURCE / "lean-toolchain").read_text().strip() != TOOLCHAIN:
        raise chunks.Refused("Unexpected Lean version")
    packages = []
    for entry in manifest["packages"]:
        path = SOURCE / manifest["packagesDir"] / entry["name"]
        head = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
        if head != entry["rev"]:
            raise chunks.Refused("Dependency revision changed: " + entry["name"])
        subprocess.run(["git", "-C", str(path), "diff", "--quiet", "HEAD", "--"], check=True)
        if entry["name"] == "mathlib" and head != REVISION:
            raise chunks.Refused("Unexpected Mathlib revision")
        packages.append({"name": entry["name"], "path": str(path), "revision": head})
    mathlib = next(p for p in packages if p["name"] == "mathlib")
    library = Path(mathlib["path"]) / ".lake/build/lib/lean"
    for module in ("Mathlib", SMOKE_MODULE):
        if not (library / (module.replace(".", "/") + ".olean")).is_file():
            raise chunks.Refused("Missing cached module: " + module + "; no automatic rebuild")
    for path in (EXPORTER, CONVERTER, LEAN / "bin/lean"):
        if not path.is_file():
            raise chunks.Refused("Missing export tool: " + str(path))
    return {"mathlib_revision": REVISION, "toolchain": TOOLCHAIN, "packages": packages,
            "manifest_sha256": chunks.sha(manifest_path)}


def lean_paths(source):
    return [LEAN / "lib/lean", *[Path(p["path"]) / ".lake/build/lib/lean" for p in source["packages"]]]


def input_hashes(source):
    # Record the actual compiled inputs, not just the source checkout's HEAD.
    paths = [Path(__file__).resolve(), EXPORTER, CONVERTER, LEAN / "bin/lean", SOURCE / "lake-manifest.json"]
    for directory in lean_paths(source):
        for suffix in ("*.olean", "*.olean.private", "*.olean.server"):
            paths.extend(sorted(directory.rglob(suffix)))
    return {str(p): chunks.sha(p) for p in paths}


def disk_gate(directory, required):
    if shutil.disk_usage(directory).free < required:
        raise chunks.Refused("Export preparation needs at least %.1f GiB free; no files were removed" % (required / GIB))


def pipeline(command, output, env, reserve=3 * GIB):
    """Stream NDJSON directly into the converter; require both exit statuses."""
    producer = subprocess.Popen(command, stdout=subprocess.PIPE, env=env, cwd=SOURCE)
    consumer = None
    try:
        consumer = subprocess.Popen([sys.executable, str(CONVERTER), "/dev/stdin", str(output)],
                                    stdin=producer.stdout, env=env, cwd=ROOT)
        producer.stdout.close()
        # Ordinary local waiting, including disk protection; no model is involved.
        while consumer.poll() is None:
            disk_gate(output.parent, reserve)
            time.sleep(2)
        convert_code = consumer.wait()
        if convert_code and producer.poll() is None:
            producer.terminate()
        export_code = producer.wait(timeout=30)
        if export_code or convert_code:
            raise chunks.Refused("Export/conversion failed (%s/%s); partial output is not reusable" %
                                 (export_code, convert_code))
    finally:
        producer.stdout.close()
        for child in (consumer, producer):
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


def verify_bundle(directory, source, module, declarations):
    record = json.loads((directory / "provenance.json").read_text())
    if (record["source"] != source or record["module"] != module
            or record["declarations"] != declarations):
        raise chunks.Refused("Export provenance does not match the selected Mathlib")
    chunks.check_entries(record["inputs"])
    export = directory / "Mathlib.lean-export"
    if chunks.sha(export) != record["export_sha256"]:
        raise chunks.Refused("Mathlib export changed")
    return export


def freeze_toolchain(directory, foundation):
    """Use the shared generation format without touching cslib's frozen files."""
    profile_path = directory / "toolchain.json"
    if profile_path.exists():
        profile = json.loads(profile_path.read_text())
        chunks.check_entries(profile["inputs"])
        if chunks.sha(profile["foundation"]) != chunks.sha(foundation):
            raise chunks.Refused("Prepared Mathlib foundation differs from the completed cslib toolchain")
        return profile_path
    directory.mkdir(parents=True, exist_ok=True)
    frozen = directory / "foundation"
    frozen.mkdir(exist_ok=False)
    for suffix in (".v", ".vo"):
        shutil.copy2(foundation.with_suffix(suffix), frozen / ("Lean" + suffix))
    paths = [generations.PLUGIN, frozen / "Lean.vo", frozen / "Lean.v", chunks.SCRIPT,
             Path(generations.__file__).resolve(), Path(__file__).resolve(),
             ROOT / "work/run-memory-guarded.sh", ROOT / "work/run-checkpoint-atomic.sh",
             ROOT / "work/run-sealed-checkpoint.sh"]
    paths.extend(generations.STDLIB.rglob("*.vo"))
    paths.extend((chunks.KERNEL / "_build/install/default/lib/coq").rglob("*.vo"))
    chunks.save_json(profile_path, {"format": 1, "foundation": str(frozen / "Lean.vo"),
                     "worker_sha256": chunks.sha(chunks.WORKER),
                     "inputs": {str(p): chunks.sha(p) for p in paths}})
    return profile_path


def prepare(smoke=False, toolchain=None):
    if toolchain is None:
        raise chunks.Refused("Mathlib needs its own pinned toolchain manifest")
    toolchain = toolchain.resolve(strict=True)
    source = inspect_source()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    target = OUTPUT / ("smoke" if smoke else "full")
    module = SMOKE_MODULE if smoke else "Mathlib"
    declarations = [SMOKE_DECLARATION] if smoke else []
    if not target.exists():
        # Stream the raw export, avoiding a second multi-GiB NDJSON file.
        disk_gate(OUTPUT, (4 if smoke else 12) * GIB)
        stage = Path(tempfile.mkdtemp(prefix="." + target.name + ".stage-", dir=OUTPUT))
        inputs = input_hashes(source)
        command = [str(EXPORTER), module, *(["--", *declarations] if declarations else [])]
        env = {**os.environ, "LEAN_PATH": os.pathsep.join(map(str, lean_paths(source))),
               "ROCQLKA_NDJSON_STREAM": "1"}
        export = stage / "Mathlib.lean-export"
        pipeline(command, export, env)
        chunks.check_entries(inputs)
        if inspect_source() != source:
            raise chunks.Refused("Source changed during export")
        chunks.save_json(stage / "provenance.json", {"source": source, "module": module,
                         "declarations": declarations, "inputs": inputs,
                         "export_sha256": chunks.sha(export), "command": command})
        # A failed stage is kept for diagnosis; it can never be mistaken for a bundle.
        os.rename(stage, target)
    export = verify_bundle(target, source, module, declarations)
    plan_path = SMOKE_PLAN if smoke else PLAN
    if not plan_path.exists():
        # The smoke deliberately crosses several save/unpack/reload boundaries.
        plan = chunks.prepare(export, plan_path.parent, "MathlibSmoke" if smoke else "Mathlib",
                              interval=100 if smoke else 2_000_000, memory_mib=2048 if smoke else 16384,
                              toolchain=toolchain)
    else:
        plan = chunks.load_plan(plan_path)
        if (plan["export"] != str(export) or plan["export_sha256"] != chunks.sha(export)
                or plan["seed"] is not None or plan["interval"] != (100 if smoke else 2_000_000)):
            raise chunks.Refused("Existing plan does not match Mathlib export/settings")
        if plan.get("toolchain") != {"path": str(toolchain), "sha256": chunks.sha(toolchain)}:
            raise chunks.Refused("Existing Mathlib plan belongs to another toolchain")
    print(json.dumps({"plan": str(plan_path), "lines": plan["lines"], "checkpoints": len(plan["chunks"])}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("inspect", "prepare"))
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--toolchain", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "inspect":
            print(json.dumps(inspect_source(), indent=2))
        else:
            # Manual invocations must use the same guarded service as the supervisor.
            if not os.environ.get("ROCQ_MEMORY_OWNER_SERVICE"):
                raise chunks.Refused("Run preparation through mathlib_loop.py (owned memory guard required)")
            OUTPUT.mkdir(parents=True, exist_ok=True)
            with (OUTPUT / "prepare.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                prepare(args.smoke, args.toolchain)
    except (chunks.Refused, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("Mathlib preparation:", exc, file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    sys.exit(main())
