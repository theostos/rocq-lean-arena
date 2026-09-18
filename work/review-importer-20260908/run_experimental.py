#!/usr/bin/env python3
"""Sequential bounded importer regressions; no compilation polling."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
review = root / "_worktrees/review"
repo = review / "importer-submit-experimental-integration-20260908"
harness = review / "arena-loop-20260908/scripts/validate_importer_review.py"
runtime = review / "rocq-experimental-runtime-20260908/_build/install/default"
stdlib = review / "stdlib-experimental-20260908/theories"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--only", action="append")
parser.add_argument("--output", type=Path, default=root / "work/review-importer-20260908/experimental-final-20260908")
args = parser.parse_args()

def git(*arguments):
    return subprocess.check_output(["git", "-C", str(repo), *arguments], text=True).strip()

boolean = ["nat_boolean_source", "nat_boolean_source_prefix", "nat_boolean_source_target",
           "nat_boolean_source_reload", "nat_boolean_adjacent", "nat_boolean_registration",
           "nat_boolean_controls"]
compact = ["compact_nat", "nat_boolean_fallback", "char_of_nat", "nat_deceq"] + boolean
nested = ["nested_containers", "nested_partial_application", "mutual_nested_recursor",
          "nested_record_containers", "nested_record_eligibility", "sprop_record_scheme",
          "nested_below", "nested_record_tree_cases", "nested_mixed_fields",
          "nested_reload_prefix", "nested_reload"]
shared = ["translation_cache_dispatch", "dependent_sprop_projection", "projection_relevance", "mutual_instances",
          "nullary_unit_scheme"] + nested + boolean
all_tests = [line[:-2] for line in (repo / "tests/_CoqProject").read_text().splitlines()
             if line.endswith(".v") and line != "core.v"] + ["core"]
topics = [
    ("compact-arithmetic", "submit/compact-arithmetic", compact +
     ["lowercase_hex", "uint32_dispatch", "string_of_list", "core"], {}, False, False),
    ("unit-like-eliminators", "submit/unit-like-eliminators",
     ["nullary_unit_scheme", "dependent_sprop_projection", "projection_relevance"] + compact + ["core"], {}, False, False),
    ("translation-sharing", "submit/translation-sharing", shared, {}, False, False),
    ("cache-validation", "submit/translation-sharing", shared,
     {"LEAN_IMPORT_VALIDATE_TRANSLATION_CACHE": "1"}, False, False),
    ("cache-disabled", "submit/translation-sharing", shared,
     {"LEAN_IMPORT_DISABLE_TRANSLATION_CACHE": "1"}, False, False),
    ("experimental-integration", "integration/importer-review-experimental",
     all_tests, {}, True, True),
]
if args.only:
    selected = set(args.only)
    unknown = selected - {topic[0] for topic in topics}
    if unknown:
        parser.error(f"unknown topics: {sorted(unknown)}")
    topics = [topic for topic in topics if topic[0] in selected]
args.output.mkdir(parents=True, exist_ok=False)
summary = {"status": "running", "runtime_revision": subprocess.check_output(
    ["git", "-C", str(runtime), "rev-parse", "HEAD"], text=True).strip(), "topics": []}

def save():
    temporary = args.output / "result.json.tmp"
    temporary.write_text(json.dumps(summary, indent=2) + "\n")
    temporary.replace(args.output / "result.json")

save()
for name, branch, tests, switches, units, strict in topics:
    revision = git("rev-parse", branch)
    worktree = review / f"importer-exp-check-{branch.rsplit('/', 1)[-1]}-{revision[:8]}-20260908"
    if not worktree.exists():
        subprocess.run(["git", "-C", str(repo), "worktree", "add", "--detach", str(worktree), revision], check=True)
    command = [sys.executable, str(harness), str(worktree), "--runtime", "experimental",
               "--runtime-prefix", str(runtime), "--stdlib", str(stdlib),
               "--output", str(args.output / name)]
    for test in tests:
        command.extend(["--test", f"tests/{test}.v"])
    if units:
        command.append("--unit-tests")
    if strict:
        command.extend(["--check-script", "tests/check_strict_import_errors.sh"])
    env = dict(os.environ)
    for key in ("LEAN_IMPORT_DISABLE_TRANSLATION_CACHE", "LEAN_IMPORT_VALIDATE_TRANSLATION_CACHE"):
        env.pop(key, None)
    env.update(switches)
    print(f"Starting {name} at {revision[:8]}", flush=True)
    with (args.output / (name + ".launcher.log")).open("wb") as log:
        code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    result_path = args.output / name / "result.json"
    detail = json.loads(result_path.read_text()) if result_path.exists() else {}
    item = {"topic": name, "branch": branch, "revision": revision,
            "status": detail.get("status", "launch-failed"), "exit_code": code,
            "cache_switches": switches, "result": str(result_path)}
    summary["topics"].append(item)
    save()
    print(json.dumps(item), flush=True)
    if code == 75:
        break
summary["status"] = "passed" if len(summary["topics"]) == len(topics) and all(
    item["exit_code"] == 0 for item in summary["topics"]) else "failed"
save()
sys.exit(0 if summary["status"] == "passed" else 1)
