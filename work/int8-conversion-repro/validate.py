#!/usr/bin/env python3
"""Fresh regression selection: no imported Lean prefix/checkpoint inputs."""
from pathlib import Path
from collections import deque
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import checkpoint_generation as gate

# Keep the existing guarded compiler, source staging and artifact-hash checks.
# Fresh drivers already cover each dependency closure; omit duplicate
# prefix/continuation/reload variants for this conversion-only change.
gate.REGRESSIONS = {
    "int8-conversion-repro": "Fresh Adjacent ProjectionBeforeEta ProjectionWrappers OpaqueUnitRecord",
    "uint32-shift-repro": "Fresh BoundedCongruence",
    "list-insert-erase-repro": "Fresh ProbeScope",
    "lrat-restore-repro": "Fresh StuckRecordEta",
    "uint32-not-repro": "Fresh ConstructorWrapper",
    "int32-min-div-repro": "Fresh Arithmetic",
    "hashmap-unit-cons-repro": "Fresh DirectDependency",
    "dhashmap-eta-repro": "EtaBeforeComputation ProjectionAliases",
    "unit-projection-repro": "ModifyEq LinearMap CanonicalUnitProjection",
    "finloop-repro": "FinLoop Int32Regression",
    "nat-bool-source-repro": "Fresh Adjacent BooleanRegistration ComparisonControls",
    "utf8-bitvec-two-repro": "Fresh Adjacent TransitiveDependency",
}

compile_once = gate.compile_test


def compile_when_available(source, logs, foundation, search_path):
    """Wait only for another owner's guard; never retry a compiler failure."""
    deadline = time.monotonic() + 300
    while True:
        try:
            return compile_once(source, logs, foundation, search_path)
        except subprocess.CalledProcessError as error:
            log = logs / (source.stem + ".guard.log")
            if (error.returncode != 75 or not log.exists()
                    or "another heavyweight run already owns" not in log.read_text()
                    or time.monotonic() >= deadline):
                run_log = logs / (source.stem + ".run.log")
                print(f"FAIL {source.parent.name} {source.stem}: exit {error.returncode}",
                      file=sys.stderr)
                for diagnostic in (run_log, log):
                    if diagnostic.exists():
                        print(f"Log: {diagnostic}", file=sys.stderr)
                        with diagnostic.open(errors="replace") as stream:
                            print("".join(deque(stream, maxlen=12)),
                                  end="", file=sys.stderr)
                raise
            time.sleep(2)


gate.compile_test = compile_when_available

if __name__ == "__main__":
    raise SystemExit(gate.main())
