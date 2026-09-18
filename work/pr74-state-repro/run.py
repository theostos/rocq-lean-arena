#!/usr/bin/env python3
"""Bounded, isolated test of plugin payload changes across .vo reloads."""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_from_start as checking
import run_mathlib_from_start as mathlib


def sha(path):
    return checking.fingerprint(path)["sha256"]


def worker(directory):
    mathlib.require_guard()
    directory = directory.resolve(strict=True)
    for name in ("Foundation.v", "Checkpoint.v", "Reload.v", "META.pr74-state-test"):
        shutil.copyfile(HERE / name, directory / name)
    template = (HERE / "payload.mlg.in").read_text()
    env = dict(os.environ, OCAMLPATH=str(directory) + os.pathsep + os.environ["OCAMLPATH"])
    compiler = [str(checking.ROCQ), "c", "-q", "-noinit", "-bytecode-compiler", "no",
                "-Q", str(directory), "", "-I", str(directory)]
    results = []

    def command(label, argv, *, cwd=directory, expect=0, message=None):
        print(label, flush=True)
        log = directory / (label + ".log")
        with log.open("x") as output:
            code = subprocess.run(["timeout", "--kill-after=5s", "60", *argv],
                                  cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT).returncode
        text = log.read_text()
        passed = (code == expect if expect is not None else code not in (0, 124, 137, 143))
        passed = passed and (message is None or message in text)
        results.append({"case": label, "exit_code": code, "expected_result": passed})
        (directory / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        if not passed:
            raise ValueError(f"Unexpected result in {label}: exit {code}; see {log}")
        return text

    def build(label, arity, tag):
        variant = directory / label
        variant.mkdir()
        source = template.replace("@ARITY@", str(arity)).replace("@TAG@", tag)
        source = source.replace("@PAYLOAD@", "(" + ", ".join(str(i) for i in range(arity)) + ")")
        (variant / "g_payload.mlg").write_text(source)
        command(label + "-coqpp", [str(checking.PREFIX / "bin/coqpp"), "g_payload.mlg"], cwd=variant)
        command(label + "-build", ["ocamlfind", "ocamlopt", "-rectypes", "-thread",
                                  "-package", "rocq-runtime.plugins.ltac", "-shared", "-linkall",
                                  "-o", "payload.cmxs", "g_payload.ml"], cwd=variant)
        shutil.copyfile(variant / "payload.cmxs", directory / "payload.cmxs")

    build("v1", 6, "PR74-PAYLOAD")
    command("01-foundation", [*compiler, "Foundation.v"])
    command("02-checkpoint", [*compiler, "Checkpoint.v"], message="expected 6 fields, received 6")
    command("03-baseline", [*compiler, "Reload.v"], message="expected 6 fields, received 6")
    old = {name: sha(directory / name) for name in ("Foundation.vo", "Checkpoint.vo", "payload.cmxs")}
    (directory / "old-hashes.json").write_text(json.dumps(old, indent=2) + "\n")

    build("v2-same-tag", 7, "PR74-PAYLOAD")
    for name in ("Foundation.vo", "Checkpoint.vo"):
        if sha(directory / name) != old[name]:
            raise ValueError("Fixture .vo changed before the partial-rebuild test")
    if sha(directory / "payload.cmxs") == old["payload.cmxs"]:
        raise ValueError("Plugin was not changed")
    command("04-plugin-only-same-tag", [*compiler, "Reload.v"], expect=None,
            message="Old payload reached the new state handler")

    build("v2-new-tag", 7, "PR74-PAYLOAD-V2")
    text = command("05-plugin-only-new-tag", [*compiler, "Reload.v"], expect=None)
    if "STATE HANDLER:" in text or not any(s in text for s in ("Not_found", "Unknown dynamic tag")):
        raise ValueError("Renamed-tag failure was not the expected missing-tag failure")

    command("06-rebuild-foundation", [*compiler, "Foundation.v"])
    if sha(directory / "Foundation.vo") == old["Foundation.vo"]:
        raise ValueError("Rebuilt foundation digest did not change")
    command("07-stale-checkpoint-new-foundation", [*compiler, "Reload.v"], expect=None,
            message="inconsistent assumptions")
    command("08-rebuild-checkpoint", [*compiler, "Checkpoint.v"], message="expected 7 fields, received 7")
    command("09-full-rebuild", [*compiler, "Reload.v"], message="expected 7 fields, received 7")
    print("All partial-rebuild controls passed.", flush=True)
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wait-for-pid", type=int)
    parser.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        return worker(args.worker)
    if args.wait_for_pid:
        try:
            pidfd = os.pidfd_open(args.wait_for_pid)
        except ProcessLookupError:
            pass
        else:
            print(f"Waiting for experiment PID {args.wait_for_pid}; no Rocq worker started.", flush=True)
            try:
                ready, _, _ = select.select([pidfd], [], [], 8 * 3600)
                if not ready:
                    raise ValueError("Experiment still active after eight hours; test not launched")
            finally:
                os.close(pidfd)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = HERE / ("run-" + stamp)
    directory.mkdir()
    link = HERE / (".latest-" + stamp)
    link.symlink_to(directory)
    os.replace(link, HERE / "latest")
    inputs = [Path(__file__).resolve(), HERE / "payload.mlg.in", checking.ROCQ,
              checking.KERNEL / "_build/default/topbin/rocqworker.exe"]
    (directory / "inputs.json").write_text(json.dumps({str(p): sha(p) for p in inputs}, indent=2) + "\n")
    env = checking.environment(1024)
    service = os.environ.get("PR74_TEST_SERVICE")
    if service:
        env["ROCQ_MEMORY_OWNER_SERVICE"] = service
    with (directory / "guard.log").open("x") as output:
        code = checking.wait_for_guard(
            ["bash", str(checking.GUARD), "timeout", "--kill-after=5s", "600",
             sys.executable, str(Path(__file__).resolve()), "--worker", str(directory)],
            cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
    (directory / "exit.json").write_text(json.dumps({"exit_code": code}) + "\n")
    print(f"Test exit {code}; logs: {directory}", flush=True)
    return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as exc:
        print(exc, file=sys.stderr)
        sys.exit(2)
