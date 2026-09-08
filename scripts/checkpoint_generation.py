#!/usr/bin/env python3
"""Fresh representation generations and model-free regression validation."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import run_chunked_import as chunks

ROOT = chunks.ROOT
IMPORTER = ROOT / "_worktrees/rocq-lean-import/compact-peano-importer-current"
PLUGIN = IMPORTER / "src/lean_import.cmxs"
STDLIB = ROOT / "_worktrees/rocq/stdlib-int32-repro/theories"
# The legacy gate plus fresh dependency prefixes and source-comparison tests.
# No .vo from the old representation enters this validation tree.
REGRESSIONS = {
    "uint32-shift-repro": "Prefix Target Fresh Widths Reload BoundedCongruence",
    "list-insert-erase-repro": "Prefix Target Fresh Reload ProbeScope",
    "lrat-restore-repro": "Prefix Target NoHeuristic Fresh Reload AccessEta StuckRecordEta",
    "uint32-not-repro": "Prefix Target Fresh Widths Reload ConstructorWrapper",
    "int32-min-div-repro": "Prefix Target Fresh Widths Reload Arithmetic",
    "hashmap-unit-cons-repro": "Prefix Target Reload Fresh DirectDependency",
    "unit-projection-repro": "ModifyEq LinearMap CanonicalUnitProjection Arithmetic",
    "finloop-repro": "FinLoop Int32Regression",
    "nat-bool-source-repro": "Fresh Prefix Target Reload Adjacent BooleanRegistration ComparisonControls",
}
EXTRA_EXPORTS = ("work/int32-tdiv-repro/Int32Tdiv.lean-export",
                 "work/nat-beq-eq-def-repro/NatBeq.lean-export")
IMPORTER_TESTS = """nullary_unit_scheme primitive_record_eliminator rec_single_ctor
projection_relevance dependent_sprop_projection sprop_record_scheme universe_instances
mutual_inductives nested_containers nested_record_containers""".split()


def source_inputs(source):
    """Collect fixture sources, including literal, relative Rocq Load commands.

    Load keeps the compiler's working directory (the top-level fixture's
    directory), including inside another loaded file. Never import old .vo files.
    """
    working_directory = source.parent
    seen = set()

    def visit(path):
        path = path.resolve(strict=True)
        if not path.is_relative_to(ROOT) or path.suffix != ".v":
            raise chunks.Refused("Regression source must be a repository .v file: " + str(path))
        if path in seen:
            return
        seen.add(path)
        for name in re.findall(r'^\s*Load\s+(?:Verbose\s+)?"([^"]+)"\s*\.', path.read_text(), re.MULTILINE):
            relative = Path(name if name.endswith(".v") else name + ".v")
            if relative.is_absolute():
                raise chunks.Refused("Regression Load must be relative: " + name)
            visit(working_directory / relative)

    visit(source)
    return sorted(seen)


def stage_source(source, destination, stage_root):
    for dependency in source_inputs(source):
        relative = os.path.relpath(dependency, source.parent)
        staged = (destination.parent / relative).resolve()
        if not staged.is_relative_to(stage_root.resolve()):
            raise chunks.Refused("Regression Load escapes the staging directory: " + str(dependency))
        staged.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(dependency, staged)


def regression_inputs():
    paths = []
    for group, names in REGRESSIONS.items():
        directory = ROOT / "work" / group
        paths.extend(directory / (n + ".v") for n in names.split())
        paths.extend(directory.glob("*.lean-export"))
    paths.extend(ROOT / name for name in EXTRA_EXPORTS)
    paths.extend(IMPORTER / "tests" / (n + ".v") for n in IMPORTER_TESTS)
    # These fixtures use ../dumps/ relative to their tests directory.
    paths.extend(p for p in (IMPORTER / "dumps").rglob("*") if p.is_file())
    loaded = [dependency for path in paths if path.suffix == ".v" for dependency in source_inputs(path)]
    return sorted(set(paths + loaded))


def representation(foundation):
    foundation = Path(foundation).resolve(strict=True)
    if foundation.name != "Lean.vo" or not foundation.is_relative_to(ROOT / "work"):
        raise chunks.Refused("Foundation must be a tested work/.../Lean.vo")
    return {str(PLUGIN): chunks.sha(PLUGIN), str(foundation): chunks.sha(foundation)}


def create(directory, previous_plan, foundation):
    """Only the supervisor calls this after a tested repair requests a restart."""
    old = chunks.load_plan(previous_plan)
    if chunks.sha(old["export"]) != old["export_sha256"]:
        raise chunks.Refused("Cannot restart against a different export")
    foundation = Path(foundation).resolve(strict=True)
    representation(foundation)
    directory.mkdir(parents=True, exist_ok=False)
    # Preserve the tested foundation even if a later repair builds elsewhere.
    frozen = directory / "foundation"
    frozen.mkdir()
    for suffix in (".v", ".vo"):
        shutil.copy2(foundation.with_suffix(suffix), frozen / ("Lean" + suffix))
    paths = [PLUGIN, frozen / "Lean.vo", frozen / "Lean.v", chunks.SCRIPT, Path(__file__).resolve(),
             ROOT / "work/run-memory-guarded.sh", ROOT / "work/run-checkpoint-atomic.sh",
             ROOT / "work/run-sealed-checkpoint.sh"]
    paths.extend(STDLIB.rglob("*.vo"))
    paths.extend((chunks.KERNEL / "_build/install/default/lib/coq").rglob("*.vo"))
    toolchain = directory / "toolchain.json"
    chunks.save_json(toolchain, {"format": 1, "foundation": str(frozen / "Lean.vo"),
                     "worker_sha256": chunks.sha(chunks.WORKER),
                     "inputs": {str(p): chunks.sha(p) for p in paths}})
    full = directory / "full"
    chunks.prepare(Path(old["export"]), full, old["library"], interval=2_000_000,
                   memory_mib=old["memory_mib"], toolchain=toolchain)
    smoke = directory / "smoke"
    chunks.prepare(ROOT / "work/uint32-shift-repro/UIntShift.lean-export", smoke, "ChunkSmoke",
                   interval=40000, memory_mib=2048, toolchain=toolchain)
    chunks.save_json(directory / "generation.json", {
        "previous_plan": str(previous_plan), "previous_plan_sha256": chunks.sha(previous_plan),
        "reason": "Representation changed; recheck from line 1 without historical checkpoints",
        "plan": str(full / "plan.json"), "smoke_plan": str(smoke / "plan.json")})
    return full / "plan.json", smoke / "plan.json"


def compile_test(source, logs, foundation, search_path):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("LEAN_IMPORT_", "ROCQ_DIAGNOSTIC_"))}
    env.pop("ROCQ_CHECKPOINT_LOGICAL_DIR", None)
    env.pop("ROCQ_CHECKPOINT_INPUTS_FILE", None)
    env.update(ROCQ_MEMORY_MAX_KIB="4194304", ROCQ_MAX_RSS_KIB="3932160",
               ROCQ_MEMORY_HIGH_KIB="4194304", ROCQ_MIN_AVAILABLE_KIB="3145728",
               ROCQ_MEMORY_SWAP_MAX_KIB="0", ROCQ_STACK_KIB="8192", ROCQ_ALLOW_EXTERNAL_ROCQ="0",
               ROCQ_MEMORY_POLL_SECONDS="0.25", OCAMLRUNPARAM="s=4M,o=80,i=15,a=2,v=0",
               ROCQ_CHECKPOINT_LOG_FILE=str(logs / (source.stem + ".run.log")))
    command = ["bash", str(ROOT / "work/run-checkpoint-atomic.sh"), str(source), "--",
               "timeout", "--signal=TERM", "--kill-after=5s", "600",
               str(chunks.KERNEL / "_build/install/default/bin/rocq"), "c", "-q",
               "-bytecode-compiler", "no", "-R", str(STDLIB), "Stdlib", "-I", str(IMPORTER / "src"),
               "-Q", str(search_path), "", "-Q", str(foundation.parent), "LeanImport"]
    with (logs / (source.stem + ".guard.log")).open("w") as out:
        subprocess.run(command, env=env, stdout=out, stderr=subprocess.STDOUT, check=True)


def validate(plan_path, directory, foundation=None):
    plan = chunks.load_plan(plan_path) if plan_path else None
    if plan:
        chunks.preflight(plan)
        foundation = Path(chunks.generation_toolchain(plan)["foundation"])
    else:
        foundation = Path(foundation).resolve(strict=True)
    tested_inputs = {**representation(foundation), str(chunks.WORKER): chunks.sha(chunks.WORKER)}
    original = {str(p): chunks.sha(p) for p in regression_inputs()}
    directory.mkdir(parents=True, exist_ok=False)
    # Recreate fixture-relative paths, but never copy old compiled artifacts.
    for group in REGRESSIONS:
        stage = directory / "work" / group
        stage.mkdir(parents=True)
        for export in (ROOT / "work" / group).glob("*.lean-export"):
            (stage / export.name).symlink_to(export)
    for relative in EXTRA_EXPORTS:
        export = directory / relative
        export.parent.mkdir(parents=True, exist_ok=True)
        export.symlink_to(ROOT / relative)
    count = 0
    for group, names in REGRESSIONS.items():
        stage = directory / "work" / group
        for name in names.split():
            source = stage / (name + ".v")
            stage_source(ROOT / "work" / group / source.name, source, directory)
            compile_test(source, stage, foundation, stage)
            count += 1
            print("PASS", group, name, flush=True)
    tests = directory / "importer/tests"
    tests.mkdir(parents=True)
    (tests.parent / "dumps").symlink_to(IMPORTER / "dumps")
    for name in IMPORTER_TESTS:
        source = tests / (name + ".v")
        stage_source(IMPORTER / "tests" / source.name, source, directory)
        compile_test(source, tests, foundation, tests)
        count += 1
        print("PASS importer", name, flush=True)
    chunks.check_entries(original)
    chunks.check_entries(tested_inputs)
    if plan:
        chunks.preflight(plan)
    subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests"], cwd=ROOT, check=True)
    chunks.save_json(directory / "passed.json", {"tests": count, "plan_sha256": chunks.sha(plan_path) if plan else None,
                     "worker_sha256": chunks.sha(chunks.WORKER)})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--plan", type=Path)
    choice.add_argument("--foundation", type=Path, help="Run candidate regressions without creating a checkpoint generation")
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()
    try:
        validate(args.plan.resolve(strict=True) if args.plan else None, args.directory.resolve(), args.foundation)
    except (chunks.Refused, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("generation validation:", exc, file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    sys.exit(main())
