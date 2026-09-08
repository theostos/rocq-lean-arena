#!/usr/bin/env python3
"""Sealed, contiguous Lean-import checkpoints; one guarded Rocq process at a time."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = Path(__file__).resolve()
KERNEL = ROOT / "_worktrees/rocq/compact-peano-view"
WORKER = KERNEL / "_build/default/topbin/rocqworker.exe"
PIN = ROOT / "work/unit-projection-repro/check-toolchain.sh"
SEED_CHECK = ROOT / "work/lrat-restore-repro/check-prefix15m.sh"
OLD_RUN = ROOT / "work/cslib-full-fresh/runs/cslib-unit-fix"
FOUNDATION = ROOT / "work/int32-tdiv-repro/foundation"
SETTINGS = '''From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 600.
'''


class Refused(Exception):
    pass


class CompileFailed(Exception):
    def __init__(self, code):
        self.code = code


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def save_json(path, value):
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as f:
        json.dump(value, f, indent=2)
        f.write("\n")
        name = f.name
    os.replace(name, path)


def immutable_text(path, text):
    if path.exists():
        if path.read_text() != text:
            raise Refused("Refusing to overwrite a different plan/source: " + str(path))
        return
    with path.open("x") as f:
        f.write(text)


def rocq_string(path):
    value = str(path)
    if any(c in value for c in "\n\r\\"):
        raise Refused("Unsupported path characters: " + repr(value))
    return '"' + value.replace('"', '""') + '"'


def boundaries(lines, start, interval):
    """Exact line intervals except when that would split consecutive #INDs.

    The importer holds consecutive #IND records as a pending mutual block.
    A non-#IND line flushes that block. Never freeze halfway through it.
    Expression/name records themselves may safely straddle a checkpoint.
    """
    target = start + interval
    ends = []
    h = hashlib.sha256()
    number = 0
    for number, raw in enumerate(lines, 1):
        h.update(raw)
        if number + 1 >= target and not raw.startswith(b"#IND "):
            ends.append(number + 1)
            target = number + 1 + interval
    if start > number + 1:
        raise Refused("Seed cursor is beyond EOF")
    if start < number + 1 and (not ends or ends[-1] != number + 1):
        ends.append(number + 1)
    return ends, number, h.hexdigest()


def prepare(export, directory, library, interval=2_000_000, start=1, seed=None, memory_mib=16384, toolchain=None):
    if not re.fullmatch(r"[A-Z][A-Za-z0-9_]*", library) or interval <= 0 or start < 1:
        raise Refused("Invalid library, interval or start line")
    if (seed is None) != (start == 1):
        raise Refused("A noninitial cursor requires a seed checkpoint")
    if not 256 <= memory_mib <= 16384:
        raise Refused("Memory budget must be 256..16384 MiB")
    export, directory = export.resolve(strict=True), directory.resolve()
    rocq_string(export)
    if (directory / "plan.json").exists():
        raise Refused("Plan already exists; use run to resume it")
    with export.open("rb") as f:
        ends, total, export_hash = boundaries(f, start, interval)
    if not ends:
        raise Refused("Nothing remains after the supplied seed")
    seed_info = None
    if seed:
        seed = seed.resolve(strict=True)
        if seed.suffix != ".vo" or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", seed.stem):
            raise Refused("Invalid seed checkpoint")
        seed_info = {"path": str(seed), "sha256": sha(seed), "module": seed.stem,
                     "source_sha256": sha(seed.with_suffix(".v"))}
    directory.mkdir(parents=True, exist_ok=True)
    previous = seed_info["module"] if seed_info else None
    chunks = []
    for end in ends:
        module = library + "To" + str(end - 1)
        chunks.append({"module": module, "start": start, "end": end, "parent": previous})
        previous, start = module, end
    plan = {"format": 1, "library": library, "export": str(export), "export_sha256": export_hash,
            "lines": total, "interval": interval, "seed": seed_info, "chunks": chunks,
            "memory_mib": memory_mib}
    if toolchain:
        if seed:
            raise Refused("A new representation must start without a historical seed")
        toolchain = Path(toolchain).resolve(strict=True)
        plan["toolchain"] = {"path": str(toolchain), "sha256": sha(toolchain)}
    for chunk in chunks:
        write_sources(directory, plan, chunk)
    save_json(directory / "plan.json", plan)
    return plan


def write_sources(directory, plan, chunk):
    parent = "Require Import " + chunk["parent"] + ".\n" if chunk["parent"] else ""
    export = rocq_string(plan["export"])
    source = SETTINGS + parent + "Lean Import %s %d %d.\n" % (export, chunk["start"], chunk["end"])
    # An empty import forces the packed parser state to unpack too, unlike Require alone.
    reload_source = SETTINGS + "Require Import " + chunk["module"] + ".\n"
    reload_source += "Lean Import %s %d %d.\n" % (export, chunk["end"], chunk["end"])
    immutable_text(directory / (chunk["module"] + ".v"), source)
    immutable_text(directory / (chunk["module"] + "Reload.v"), reload_source)


def load_plan(path):
    plan = json.loads(path.read_text())
    if plan["format"] != 1 or not plan["chunks"] or not 256 <= plan["memory_mib"] <= 16384:
        raise Refused("Unsupported or empty checkpoint plan")
    cursor = plan["chunks"][0]["start"]
    parent = plan["seed"]["module"] if plan["seed"] else None
    if not plan["seed"] and cursor != 1:
        raise Refused("Unseeded plan must begin at line 1")
    for chunk in plan["chunks"]:
        expected_name = plan["library"] + "To" + str(chunk["end"] - 1)
        if (chunk["start"] != cursor or chunk["end"] <= cursor
                or chunk["parent"] != parent or chunk["module"] != expected_name
                or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", expected_name)):
            raise Refused("Checkpoint plan has a gap, overlap or invalid module")
        cursor, parent = chunk["end"], chunk["module"]
        write_sources(path.parent, plan, chunk)
    if cursor != plan["lines"] + 1:
        raise Refused("Checkpoint plan does not cover EOF")
    return plan


def manifest_entries(path):
    entries = {}
    for line in path.read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match or not Path(match[2]).is_absolute():
            raise Refused("Malformed manifest: " + str(path))
        if match[2] in entries and entries[match[2]] != match[1]:
            raise Refused("Conflicting manifest entries")
        entries[match[2]] = match[1]
    if not entries:
        raise Refused("Empty manifest: " + str(path))
    return entries


def check_entries(entries, allow_worker_migration=False):
    migrations = []
    for name, expected in entries.items():
        current = sha(name)
        if current != expected:
            # The current worker is separately pinned/tested. Never rewrite the
            # producer seal, or extend this exception to the importer/proof inputs.
            if allow_worker_migration and Path(name) in (WORKER, PIN):
                migrations.append({"path": name, "producer": expected, "current": current})
            else:
                raise Refused("Checkpoint input/artifact changed: " + name)
    return migrations


def verify_saved(directory, chunk):
    module = chunk["module"]
    artifact, seal = directory / (module + ".vo"), directory / (module + ".seal")
    if not artifact.exists() and not seal.exists():
        return None
    if not artifact.is_file() or not seal.is_dir():
        raise Refused("Incomplete checkpoint/seal pair: " + module)
    inputs = manifest_entries(seal / "inputs.sha256")
    source = directory / (module + ".v")
    if str(source) not in inputs or str(directory / "plan.json") not in inputs:
        raise Refused("Checkpoint is not bound to its source and plan")
    artifacts = manifest_entries(seal / "artifact.sha256")
    if set(artifacts) != {str(artifact)}:
        raise Refused("Unexpected checkpoint artifact")
    migrations = check_entries(inputs, allow_worker_migration=True)
    check_entries(artifacts)
    return migrations


def preflight(plan, seed_check=True):
    if plan.get("toolchain"):
        profile = generation_toolchain(plan)
        check_entries(profile["inputs"])
        # A subsequent kernel-only fix may reuse this representation. Approval
        # comes from the supervisor's completed repair/validation handoff.
        expected_worker = os.environ.get("ROCQ_APPROVED_WORKER_SHA256", profile["worker_sha256"])
        if sha(WORKER) != expected_worker:
            raise Refused("Current worker is not the approved generation worker")
    else:
        subprocess.run(["bash", str(PIN)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    if sha(plan["export"]) != plan["export_sha256"]:
        raise Refused("Export identity changed; cannot reuse this chain")
    seed = plan["seed"]
    if seed:
        path = Path(seed["path"])
        if sha(path) != seed["sha256"] or sha(path.with_suffix(".v")) != seed["source_sha256"]:
            raise Refused("Seed checkpoint changed")
        if seed_check:
            if path != OLD_RUN / "Prefix15M.vo":
                raise Refused("No approved migration checker for this seed")
            subprocess.run(["bash", str(SEED_CHECK)], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)


def generation_toolchain(plan):
    ref = plan["toolchain"]
    path = Path(ref["path"])
    if sha(path) != ref["sha256"]:
        raise Refused("Generation toolchain manifest changed")
    profile = json.loads(path.read_text())
    if profile.get("format") != 1 or plan["seed"] is not None:
        raise Refused("Invalid generation toolchain or historical seed")
    foundation = Path(profile["foundation"])
    if (not foundation.is_absolute() or foundation.name != "Lean.vo"
            or str(foundation) not in profile["inputs"]
            or str(ROOT / "_worktrees/rocq-lean-import/compact-peano-importer-current/src/lean_import.cmxs") not in profile["inputs"]):
        raise Refused("Generation manifest must bind the importer and foundation")
    return profile


def compile_module(directory, module, attempt, sealed, inputs, memory_mib=16384):
    plan = json.loads((directory / "plan.json").read_text())
    foundation = (Path(generation_toolchain(plan)["foundation"]).parent
                  if plan.get("toolchain") else FOUNDATION)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("LEAN_IMPORT_", "ROCQ_DIAGNOSTIC_"))}
    env.pop("ROCQ_CHECKPOINT_LOGICAL_DIR", None)
    env.update(OCAMLRUNPARAM="s=4M,o=80,i=15,a=2,v=0",
               ROCQ_MAX_RSS_KIB=str(memory_mib * 1024 * 15 // 16),
               ROCQ_MEMORY_MAX_KIB=str(memory_mib * 1024),
               ROCQ_MEMORY_HIGH_KIB=str(memory_mib * 1024), ROCQ_MIN_AVAILABLE_KIB="3145728",
               ROCQ_MEMORY_SWAP_MAX_KIB="0", ROCQ_STACK_KIB="262144",
               ROCQ_ALLOW_EXTERNAL_ROCQ="0", ROCQ_MEMORY_POLL_SECONDS="0.25",
               LEAN_IMPORT_CHECKPOINT_STATS="1", ROCQ_CHECKPOINT_INPUTS_FILE=str(inputs),
               ROCQ_CHECKPOINT_LOG_FILE=str(attempt / (module + ".run.log")))
    runner = ROOT / "work" / ("run-sealed-checkpoint.sh" if sealed else "run-checkpoint-atomic.sh")
    cmd = ["bash", str(runner), str(directory / (module + ".v")), "--",
           "timeout", "--signal=TERM", "--kill-after=5s", "28800",
           str(KERNEL / "_build/install/default/bin/rocq"), "c", "-q", "-bytecode-compiler", "no",
           "-R", str(ROOT / "_worktrees/rocq/stdlib-int32-repro/theories"), "Stdlib",
           "-I", str(ROOT / "_worktrees/rocq-lean-import/compact-peano-importer-current/src"),
           "-Q", str(OLD_RUN), "", "-Q", str(directory), "",
           "-Q", str(foundation), "LeanImport"]
    if plan.get("toolchain"):
        # New terms cannot accidentally resolve a module from the old chain.
        old_mapping = cmd.index(str(OLD_RUN))
        del cmd[old_mapping - 1:old_mapping + 2]
    print("Starting", module, flush=True)
    with (attempt / (module + ".guard.log")).open("w") as log:
        code = subprocess.run(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    if code:
        raise CompileFailed(code)
    print("Passed", module, flush=True)


def current_inputs(plan_path, plan, predecessors):
    paths = [plan_path, Path(plan["export"]), SCRIPT, WORKER,
             ROOT / "work/run-sealed-checkpoint.sh"]
    if plan.get("toolchain"):
        profile = generation_toolchain(plan)
        check_entries(profile["inputs"])
        paths.extend([Path(plan["toolchain"]["path"]), *map(Path, profile["inputs"])])
    else:
        paths.extend([PIN, SEED_CHECK])
        paths.extend(Path(p) for p in manifest_entries(OLD_RUN / "inputs.sha256") if Path(p) != WORKER)
    if plan["seed"]:
        paths.extend([Path(plan["seed"]["path"]), Path(plan["seed"]["path"]).with_suffix(".v")])
    for chunk in predecessors:
        paths.extend([plan_path.parent / (chunk["module"] + ".vo"),
                      plan_path.parent / (chunk["module"] + ".v")])
    return {str(p): sha(p) for p in paths}


def check_disk(directory, previous=None):
    # Admission estimate, not a filesystem quota. Preserve room for other work
    # and for atomic staging/reload; never delete checkpoints to make space.
    estimate = max(2 * 1024**3, 4 * previous.stat().st_size if previous else 0)
    required = 3 * 1024**3 + estimate
    if shutil.disk_usage(directory).free < required:
        raise Refused("Insufficient disk space: need %.1f GiB free (reserve + staging estimate)" %
                      (required / 1024**3))


def run(plan_path, attempt, pause_file=None):
    directory = plan_path.parent
    plan = load_plan(plan_path)
    attempt.mkdir(parents=True, exist_ok=False)
    status = {"format": "chunked-import-v1", "plan": str(plan_path), "phase": "preflight"}
    def record(**fields):
        status.update(fields)
        save_json(attempt / "status.json", status)
    def pause_boundary():
        if pause_file and pause_file.exists():
            record(phase="paused")
            raise CompileFailed(75)
    record()
    pause_boundary()
    # Same lock as the original launcher; no manual full pass can overlap.
    with (OLD_RUN / "launcher.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise CompileFailed(75) from None
        preflight(plan)
        count = 0
        migrations = []
        for chunk in plan["chunks"]:
            saved = verify_saved(directory, chunk)
            if saved is None:
                break
            count += 1
            migrations.extend(saved)
        if any((directory / (c["module"] + ".vo")).exists()
               or (directory / (c["module"] + ".seal")).exists() for c in plan["chunks"][count + 1:]):
            raise Refused("Saved checkpoints are not a contiguous prefix")
        record(migrations=migrations)
        def reload(chunk):
            check_disk(directory, directory / (chunk["module"] + ".vo"))
            record(phase="reloading", module=chunk["module"] + "Reload", next_line=chunk["end"])
            inputs = current_inputs(plan_path, plan, plan["chunks"][:plan["chunks"].index(chunk) + 1])
            compile_module(directory, chunk["module"] + "Reload", attempt, False,
                           attempt / "unused-for-unsealed-reload", plan["memory_mib"])
            check_entries(inputs)
            verify_saved(directory, chunk)
            save_json(directory / "progress.json", {"plan_sha256": sha(plan_path),
                      "module": chunk["module"], "next_line": chunk["end"],
                      "worker_sha256": sha(WORKER), "artifact_sha256": sha(directory / (chunk["module"] + ".vo")),
                      "reload_sha256": sha(directory / (chunk["module"] + "Reload.vo"))})
        if count:
            reload(plan["chunks"][count - 1])
        for index in range(count, len(plan["chunks"])):
            pause_boundary()
            chunk = plan["chunks"][index]
            previous = directory / (plan["chunks"][index - 1]["module"] + ".vo") if index else (
                Path(plan["seed"]["path"]) if plan["seed"] else None)
            check_disk(directory, previous)
            inputs = current_inputs(plan_path, plan, plan["chunks"][:index])
            manifest = attempt / (chunk["module"] + ".inputs.sha256")
            immutable_text(manifest, "".join(h + "  " + p + "\n" for p, h in inputs.items()))
            record(phase="importing", module=chunk["module"], start=chunk["start"], end=chunk["end"])
            compile_module(directory, chunk["module"], attempt, True, manifest, plan["memory_mib"])
            check_entries(inputs)
            verify_saved(directory, chunk)
            reload(chunk)
        record(phase="complete", next_line=plan["lines"] + 1)
        save_json(directory / "complete.json", status)
        print("Full chunked continuation, sealing and fresh reload passed.", flush=True)


def verify_complete(plan_path):
    plan = load_plan(plan_path)
    preflight(plan)
    for chunk in plan["chunks"]:
        if verify_saved(plan_path.parent, chunk) is None:
            raise Refused("The chain is incomplete")
    progress = json.loads((plan_path.parent / "progress.json").read_text())
    completion = json.loads((plan_path.parent / "complete.json").read_text())
    final = plan["chunks"][-1]
    if (progress["next_line"] != plan["lines"] + 1 or progress["module"] != final["module"]
            or progress["plan_sha256"] != sha(plan_path) or progress["worker_sha256"] != sha(WORKER)
            or progress["artifact_sha256"] != sha(plan_path.parent / (final["module"] + ".vo"))
            or progress["reload_sha256"] != sha(plan_path.parent / (final["module"] + "Reload.vo"))
            or completion["phase"] != "complete" or completion["next_line"] != plan["lines"] + 1):
        raise Refused("Final checkpoint has not been reloaded with the current worker")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    prepare_cli = sub.add_parser("prepare")
    prepare_cli.add_argument("--export", type=Path, required=True)
    prepare_cli.add_argument("--directory", type=Path, required=True)
    prepare_cli.add_argument("--library", required=True)
    prepare_cli.add_argument("--interval", type=int, default=2_000_000)
    prepare_cli.add_argument("--from-line", type=int, default=1)
    prepare_cli.add_argument("--seed", type=Path)
    prepare_cli.add_argument("--memory-mib", type=int, default=16384)
    prepare_cli.add_argument("--toolchain", type=Path)
    for name in ("run", "verify"):
        p = sub.add_parser(name)
        p.add_argument("--plan", type=Path, required=True)
        if name == "run":
            p.add_argument("--attempt", type=Path, required=True)
            p.add_argument("--pause-file", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            plan = prepare(args.export, args.directory, args.library, args.interval,
                           args.from_line, args.seed, args.memory_mib, args.toolchain)
            print(json.dumps({"lines": plan["lines"], "checkpoints_through": [c["end"] - 1 for c in plan["chunks"]]}))
        elif args.command == "run":
            run(args.plan.resolve(strict=True), args.attempt.resolve(), args.pause_file)
        else:
            verify_complete(args.plan.resolve(strict=True))
    except CompileFailed as exc:
        return exc.code if exc.code > 0 else 128 - exc.code
    except (Refused, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("chunked import:", exc, file=sys.stderr)
        return 65
    return 0


if __name__ == "__main__":
    sys.exit(main())
