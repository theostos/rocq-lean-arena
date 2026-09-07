#!/usr/bin/env python3
"""Read-only checks of one full-import run's evidence, not a proof checker.

The manifest supplies the expected EOF and hashes of the input, driver and
toolchain. Passing does not establish soundness, upstream compatibility, or
fresh-process reload: those are separate gates. Logs are read incrementally.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
from typing import Iterable


PROGRESS = re.compile(r"^line (\d+): (.*)$")
COUNT = re.compile(r"^- (\d+) (names|expression nodes)$")
ENTRIES = re.compile(r"^- (\d+) entries \((\d+) possible instances\)")
ERROR = re.compile(
    r"^(?:Stopped!|Skipping:|Skipped [1-9]\d*\b|Error(?: at line \d+|:)"
    r"|Anomaly\b|Lean import line timed out\.)"
)
FINISHED = re.compile(r"^memory guard: finished with status (\d+);")
PROMOTED = "checkpoint runner: atomically promoted "


def inspect_logs(
    run_lines: Iterable[str], guard_lines: Iterable[str],
    expected: dict, artifact: Path,
) -> dict:
    problems = []
    counts = {}
    entries = None
    possible_instances = None
    last_line = None
    saw_final_entry = False
    done = 0
    for raw in run_lines:
        line = raw.rstrip("\n")
        if match := PROGRESS.fullmatch(line):
            number, name = int(match[1]), match[2]
            if done:
                problems.append("progress appeared after the completion summary")
            last_line = number
            saw_final_entry |= (number, name) == (
                expected["last_line"], expected["last_name"],
            )
            # Lean names can contain diagnostic words; do not scan their text.
            continue
        if ERROR.match(line) and len(problems) < 10:
            problems.append(line)
        if line == "Done!":
            done += 1
        if match := COUNT.fullmatch(line):
            key = match[2].replace(" ", "_")
            if key in counts or done != 1:
                problems.append("unexpected or repeated summary count: " + key)
            counts[key] = int(match[1])
        if match := ENTRIES.match(line):
            if entries is not None or done != 1:
                problems.append("unexpected or repeated entry summary")
            entries, possible_instances = int(match[1]), int(match[2])

    if done != 1:
        problems.append("expected exactly one Done! summary")
    if last_line != expected["last_line"] or not saw_final_entry:
        problems.append("expected final source entry was not reached")
    for key in ("names", "expression_nodes"):
        if counts.get(key) != expected[key]:
            problems.append("missing or mismatched " + key)
    if entries is None or entries <= 0:
        problems.append("missing nonempty entry summary")

    statuses = []
    promotions = []
    for raw in guard_lines:
        line = raw.rstrip("\n")
        if match := FINISHED.match(line):
            statuses.append(int(match[1]))
        if line.startswith(PROMOTED):
            promotions.append(Path(line.removeprefix(PROMOTED)).resolve())
        if line.startswith(("memory guard: stopping", "checkpoint runner: command failed",
                            "checkpoint runner: guarded transaction failed")):
            problems.append(line)
    if statuses != [0]:
        problems.append("missing unique successful guard termination")
    if promotions != [artifact.resolve()]:
        problems.append("missing unique promotion of the expected artifact")
    return {
        "problems": problems,
        "last_progress_line": last_line,
        "counts": counts,
        "entries": entries,
        # This is deliberately not called a count of checked instances.
        "possible_instances": possible_instances,
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit(manifest_path: Path) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    base = manifest_path.resolve().parent
    artifact = (base / manifest["artifact"]).resolve()
    with (base / manifest["run_log"]).open(encoding="utf-8") as run_log, \
         (base / manifest["guard_log"]).open(encoding="utf-8") as guard_log:
        result = inspect_logs(run_log, guard_log, manifest["expected"], artifact)
    # No large file hashing while the logs still show an unfinished run.
    if not result["problems"]:
        identities = manifest["sha256"]
        if not identities:
            result["problems"].append("missing input/toolchain identities")
        for path, expected in identities.items():
            if sha256_file(base / path) != expected:
                result["problems"].append("SHA-256 mismatch: " + path)
        if not artifact.is_file() or artifact.stat().st_size == 0:
            result["problems"].append("missing or empty saved artifact")
        elif not result["problems"]:
            result["artifact_sha256"] = sha256_file(artifact)
    result["run_evidence_complete"] = not result["problems"]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        result = audit(args.manifest)
    except (OSError, ValueError, KeyError, TypeError) as error:
        result = {"run_evidence_complete": False, "problems": [str(error)]}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["run_evidence_complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
