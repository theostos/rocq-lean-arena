#!/usr/bin/env python3
"""One sequential stock-runtime validation batch; no model polling needed."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
review = root / "_worktrees/review"
harness = review / "arena-loop-20260908/scripts/validate_importer_review.py"
runtime = review / "rocq-upstream-runtime-20260908/_build/install/default"
stdlib = review / "stdlib-upstream-20260908/theories"
extra = sys.argv[1:] == ["--extra"]
fixed = sys.argv[1:] == ["--fixed"]
output = root / ("work/review-importer-20260908/stock-fixed-20260908" if fixed
                 else "work/review-importer-20260908/stock-extra-20260908" if extra
                 else "work/review-importer-20260908/stock-batch-20260908")
output.mkdir(exist_ok=False)

dependent = ["projection_relevance", "dependent_sprop_projection", "universe_instances"]
mutual = ["mutual_inductives", "mutual_instances"]
nested = ["nested_containers", "nested_partial_application", "mutual_nested_recursor",
          "nested_record_containers", "nested_record_eligibility", "sprop_record_scheme",
          "nested_below", "nested_record_tree_cases", "nested_mixed_fields",
          "nested_reload_prefix", "nested_reload"]
records = ["primitive_record_eliminator", "primitive_record_reload_prefix", "primitive_record_reload"]
controls = ["reducibility_controls", "reducibility_controls_reload"]
topics = [
    ("universe-instances", ["universe_instances", "ulift"], False),
    ("dependent-projections", dependent, False),
    ("mutual-inductives", mutual + dependent, False),
    ("nested-recursors", nested, False),
    ("primitive-record-eliminators", records + ["dependent_sprop_projection", "nested_reload_prefix", "nested_reload"], False),
    ("constructor-owners", ["constructor_owner"] + mutual + dependent, False),
    ("uint32-constructor", ["uint32_dispatch"], False),
    ("string-of-list", ["string_of_list", "uint32_dispatch"], False),
    ("strict-import-errors", ["lowercase_hex", "ulift"], False),
    ("reducibility-hints", controls, True),
    ("parser-sharing", controls, True),
    ("stock-integration", dependent + mutual + ["constructor_owner", "uint32_dispatch", "string_of_list"]
     + nested + records + ["ulift", "rec_single_ctor", "lowercase_hex"], False),
]
if extra:
    topics = [
        ("reducibility-hints", controls, True),
        ("parser-sharing", controls, True),
        ("nested-recursors", nested[6:], False),
        ("primitive-record-eliminators", ["nested_reload_prefix", "nested_reload"], False),
        ("stock-integration", ["projection_relevance", "universe_instances"] + mutual
         + ["constructor_owner", "uint32_dispatch", "string_of_list"]
         + [test for test in nested if test != "sprop_record_scheme"] + records
         + ["ulift", "rec_single_ctor", "lowercase_hex"], True),
        ("indexed-checkpoints", ["checkpoint_prefix", "checkpoint_middle", "checkpoint_end", "checkpoint_reload",
                                  "nested_reload_prefix", "nested_reload",
                                  "primitive_record_reload_prefix", "primitive_record_reload"], True),
    ]
if fixed:
    topics = [(name, tests, units) for name, tests, units in topics
              if name not in ("universe-instances", "uint32-constructor", "string-of-list")]
    topics = [(name, tests + (["strict_import_errors"] if name in
                              ("strict-import-errors", "reducibility-hints", "parser-sharing") else []), units)
              for name, tests, units in topics]
    topics = [(name, tests + controls + ["strict_import_errors"], True)
              if name == "stock-integration" else (name, tests, units)
              for name, tests, units in topics]
    topics = [(name, tests + ["core"], units) if name == "stock-integration"
              else (name, tests, units) for name, tests, units in topics]
    topics.extend([("uint32-constructor", ["uint32_dispatch", "core"], False),
                   ("string-of-list", ["string_of_list", "uint32_dispatch", "core"], False)])
    topics.append(("indexed-checkpoints", ["checkpoint_prefix", "checkpoint_middle", "checkpoint_end", "checkpoint_reload",
                                            "nested_reload_prefix", "nested_reload",
                                            "primitive_record_reload_prefix", "primitive_record_reload",
                                            *controls, "strict_import_errors"], True))
summary = {"status": "running", "runtime": str(runtime), "stdlib": str(stdlib), "topics": []}


def save():
    temporary = output / "result.json.tmp"
    temporary.write_text(json.dumps(summary, indent=2) + "\n")
    temporary.replace(output / "result.json")


save()
for name, tests, units in topics:
    worktree = review / f"importer-check-{name}-20260908"
    command = [sys.executable, str(harness), str(worktree), "--runtime", "stock",
               "--runtime-prefix", str(runtime), "--stdlib", str(stdlib), "--output", str(output / name)]
    for test in tests:
        command.extend(["--test", f"tests/{test}.v"])
    if units:
        command.append("--unit-tests")
    if fixed and name in ("strict-import-errors", "reducibility-hints", "parser-sharing", "stock-integration", "indexed-checkpoints"):
        command.extend(["--check-script", "tests/check_strict_import_errors.sh"])
    print(f"Starting topic {name}", flush=True)
    with (output / (name + ".launcher.log")).open("wb") as log:
        code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT).returncode
    result_path = output / name / "result.json"
    details = json.loads(result_path.read_text()) if result_path.exists() else {}
    result = {"topic": name, "revision": details.get("revision"), "exit_code": code,
              "status": details.get("status", "launch-failed"), "result": str(result_path)}
    summary["topics"].append(result)
    save()
    print(json.dumps(result), flush=True)
    if code == 75:
        print("Resource guard refused a launch; leaving the batch stopped.", flush=True)
        break
summary["status"] = "passed" if len(summary["topics"]) == len(topics) and all(
    item["exit_code"] == 0 for item in summary["topics"]) else "failed"
save()
print(f"Batch {summary['status']}: {output / 'result.json'}", flush=True)
sys.exit(0 if summary["status"] == "passed" else 1)
