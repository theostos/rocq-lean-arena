#!/usr/bin/env python3
"""Resume the existing Mathlib chain with a recorded timeout-only override."""

import argparse
import json
import os
from pathlib import Path
import tempfile

import mathlib_ndjson_loop as driver

chunks = driver.chunks
SCRIPT = Path(__file__).resolve()


def source_texts(plan, chunk, timeout):
    export = chunks.rocq_string(plan["export"])
    parent = "Require Import " + chunk["parent"] + ".\n" if chunk["parent"] else ""
    for module, require, start, end in (
        (chunk["module"], parent, chunk["start"], chunk["end"]),
        (chunk["module"] + "Reload", "Require Import " + chunk["module"] + ".\n",
         chunk["end"], chunk["end"]),
    ):
        command = "Lean Import %s %d %d.\n" % (export, start, end)
        original = chunks.SETTINGS + require + command
        settings = chunks.SETTINGS.replace("Set Lean Line Timeout 600.\n", "")
        replacement = settings + require + f"Set Lean Line Timeout {timeout}.\n" + command
        yield module, original, replacement


def update_sources(directory, plan, chunk, timeout):
    sources = list(source_texts(plan, chunk, timeout))
    for module, original, replacement in sources:
        path = directory / (module + ".v")
        current = path.read_text() if path.exists() else None
        if current != replacement:
            if path.with_suffix(".vo").exists() or path.with_suffix(".seal").exists():
                raise chunks.Refused("Cannot change a compiled checkpoint source: " + str(path))
            if current is not None and current != original:
                raise chunks.Refused("Unexpected checkpoint source: " + str(path))
    for module, original, replacement in sources:
        path = directory / (module + ".v")
        if not path.exists():
            chunks.immutable_text(path, replacement)
        elif path.read_text() != replacement:
            with tempfile.NamedTemporaryFile("w", dir=directory, delete=False) as stream:
                stream.write(replacement)
                temporary = stream.name
            os.replace(temporary, path)


def install_override(directory, timeout):
    if timeout <= 600:
        raise chunks.Refused("The resume timeout must exceed the original 600 seconds")
    plan = json.loads((directory / "checkpoints/plan.json").read_text())
    policy_path = directory / "timeout-override.json"
    if policy_path.exists():
        policy = json.loads(policy_path.read_text())
        if policy.get("format") != 1 or policy.get("line_timeout") != timeout:
            raise chunks.Refused("The recorded timeout override differs from this request")
    else:
        progress = json.loads((directory / "checkpoints/progress.json").read_text())
        policy = {"format": 1, "from_line": progress["next_line"], "line_timeout": timeout}
    if policy["from_line"] not in {chunk["start"] for chunk in plan["chunks"]}:
        raise chunks.Refused("The timeout override must begin at a checkpoint boundary")
    chunks.immutable_text(policy_path, json.dumps(policy, indent=2) + "\n")
    original_write_sources = chunks.write_sources
    original_inputs = chunks.current_inputs

    def write_sources(directory, plan, chunk):
        if chunk["start"] < policy["from_line"]:
            original_write_sources(directory, plan, chunk)
        else:
            update_sources(directory, plan, chunk, timeout)

    def current_inputs(*args):
        inputs = original_inputs(*args)
        inputs.update({str(path): chunks.sha(path) for path in (SCRIPT, policy_path)})
        return inputs

    chunks.write_sources = write_sources
    chunks.current_inputs = current_inputs
    return policy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=driver.STATE)
    parser.add_argument("--line-timeout", type=int, default=1800)
    args = parser.parse_args()
    directory = args.directory.resolve()
    policy = install_override(directory, args.line_timeout)
    print(json.dumps({"timeout_override": policy}), flush=True)
    return driver.run(directory, smoke=False, memory_mib=16384)


if __name__ == "__main__":
    raise SystemExit(main())
