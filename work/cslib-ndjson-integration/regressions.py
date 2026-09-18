#!/usr/bin/env python3
"""Compare both readers, then check each fixture through both routes, sequentially."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import run_cslib_ndjson as direct

checking = direct.checking
TASK = Path(__file__).resolve().parent
CONVERTER = ROOT / "_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py"
FIXTURES = [
    ("BinaryTree", checking.IMPORTER / "dumps/bin_tree.ndjson", "Check Scratch_BinTree.\n"),
    ("Mutual", ROOT / "_deps/lean-kernel-arena/_build/tests/repros/audit-mutual-inductives.ndjson", ""),
    ("NestedRecord", ROOT / "_deps/lean-kernel-arena/_build/tests/repros/nested-record-tree-cases.ndjson",
     "Check JsonLike_casesOn.\nCheck JsonLike_brecOn.\n"),
    ("MixedFields", ROOT / "_deps/lean-kernel-arena/_build/tests/repros/nested-mixed-fields.ndjson", ""),
    ("DiscrTree", ROOT / "_deps/lean-kernel-arena/_build/tests/repros/discrtree-cases-on.ndjson", ""),
    ("NatBeq", ROOT / "work/nat-beq-eq-def-repro/NatBeq.ndjson", ""),
    ("Unit", ROOT / "work/finloop-repro/NullaryUnit.ndjson",
     "Check choose_eq.\nCheck chooseDep_eq.\nCheck unitMatch_eq.\nCheck unbox_eq.\n"
     "Fail Definition wrong_bit : bitValue Bit_off = bitValue Bit_on := eq_refl _.\n"
     "Fail Definition wrong_box : unbox (Box_mk (Nat_succ Nat_zero)) = Nat_zero := eq_refl _.\n"),
    ("QuotientRecord", ROOT / "work/mathlib-extdtree-repro/minimal-focused-baseline/Minimal.ndjson", ""),
]


def run(command, directory, name):
    with (directory / (name + ".log")).open("x") as log:
        subprocess.run(command, cwd=directory, stdout=log, stderr=subprocess.STDOUT, check=True)
    print("PASS", name, flush=True)


def worker(directory):
    if (os.environ.get("_ROCQ_MEMORY_GUARD_SCOPED") != "1"
            or not Path("/proc/self/cgroup").read_text().strip().endswith("/rocq-lean-import-heavy.scope")):
        raise ValueError("Regression worker requires the memory guard")
    foundation = directory / "foundation"
    foundation.mkdir()
    shutil.copyfile(checking.IMPORTER / "src/Lean.v", foundation / "Lean.v")
    common = [str(checking.ROCQ), "c", "-q", "-bytecode-compiler", "no",
              "-R", str(checking.STDLIB), "Stdlib", "-I", str(checking.IMPORTER / "src"),
              "-Q", str(directory), "DirectTest", "-Q", str(foundation), "LeanImport"]
    run([*common, str(foundation / "Lean.v")], directory, "Foundation")
    for name, source, checks in FIXTURES:
        converted = directory / (name + ".lean-export")
        run([sys.executable, str(CONVERTER), str(source), str(converted)], directory, name + "Convert")
        run([str(TASK / "compare.exe"), str(source), str(converted)], directory, name + "Compare")
        for route, exported in (("Direct", source), ("Legacy", converted)):
            module = name + route
            text = checking.full_source(exported, checking.fingerprint(exported)["lines"], 30) + checks
            (directory / (module + ".v")).write_text(text)
            run([*common, module + ".v"], directory, module)
            if not (directory / (module + ".vo")).is_file():
                raise ValueError("Missing compiled output: " + module)
    (directory / "Reload.v").write_text("\n".join(
        "From DirectTest Require Import " + name + "Direct." for name, _, _ in FIXTURES) + "\n")
    run([*common, "Reload.v"], directory, "Reload")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--worker":
        worker(Path(sys.argv[2]))
    else:
        directory = Path(tempfile.mkdtemp(prefix="checks-", dir=TASK))
        print("Logs:", directory, flush=True)
        with (directory / "guard.log").open("x") as log:
            code = checking.wait_for_guard(
                ["bash", str(checking.GUARD), "timeout", "240s", sys.executable,
                 str(Path(__file__).resolve()), "--worker", str(directory)],
                env=direct.environment(4096), stdout=log, stderr=subprocess.STDOUT)
        print("Exit:", code, "—", directory / "guard.log", flush=True)
        raise SystemExit(code)
