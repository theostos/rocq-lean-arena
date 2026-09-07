"""Small synthetic evidence tests. No Rocq, guard or cgroup is started."""

from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    "full_audit", Path(__file__).resolve().parents[1] / "audit_rocq_full_pass.py",
)
assert SPEC is not None and SPEC.loader is not None
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)

EXPECTED = {"last_line": 42, "last_name": "Example.last", "names": 17,
            "expression_nodes": 36}
RUN = """line 1: First
line 42: Example.last
Done!
- 4 entries (8 possible instances) (including quot).
- 2 universe expressions
- 17 names
- 36 expression nodes
Max universe instance length 1.
"""


class LogEvidenceTests(unittest.TestCase):
    artifact = Path("/example/Full.vo")
    guard = (
        "checkpoint runner: atomically promoted /example/Full.vo\n"
        "memory guard: finished with status 0; cgroup peak=123 KiB\n"
    )

    def inspect(self, run=RUN, guard=None, expected=EXPECTED):
        return audit.inspect_logs(run.splitlines(True),
                                  (self.guard if guard is None else guard).splitlines(True),
                                  expected, self.artifact)

    def test_complete_evidence(self):
        result = self.inspect()
        self.assertEqual(result["problems"], [])
        self.assertEqual(result["entries"], 4)
        self.assertEqual(result["possible_instances"], 8)

    def test_done_alone_is_not_completion(self):
        self.assertTrue(self.inspect("Done!\n")["problems"])

    def test_zero_exit_without_summary(self):
        self.assertTrue(self.inspect("line 42: Example.last\n")["problems"])

    def test_wrong_frontier(self):
        for run in (RUN.replace("line 42:", "line 41:"),
                    RUN.replace("Example.last", "Example.other")):
            self.assertTrue(self.inspect(run)["problems"])

    def test_missing_or_incorrect_counts(self):
        for old, new in (("17 names", "16 names"),
                         ("36 expression nodes", "35 expression nodes"),
                         ("- 17 names\n", ""),
                         ("- 4 entries (8 possible instances) (including quot).\n", "")):
            with self.subTest(old=old):
                self.assertTrue(self.inspect(RUN.replace(old, new))["problems"])

    def test_repeated_or_misordered_summary(self):
        for run in (RUN + "Done!\n", RUN + "- 17 names\n",
                    "- 17 names\n" + RUN, RUN + "line 42: Example.last\n"):
            self.assertTrue(self.inspect(run)["problems"])

    def test_errors_cannot_be_hidden_by_success_markers(self):
        for diagnostic in ("Stopped!", "Skipping: Error at line 3", "Skipped 1",
                           "Error: invalid term", "Anomaly broken invariant",
                           "Lean import line timed out."):
            with self.subTest(diagnostic=diagnostic):
                self.assertTrue(self.inspect(diagnostic + "\n" + RUN)["problems"])

    def test_error_words_in_lean_name(self):
        name = "Error: Skipped 1 Anomaly"
        result = self.inspect(RUN.replace("Example.last", name),
                              expected={**EXPECTED, "last_name": name})
        self.assertEqual(result["problems"], [])

    def test_missing_or_failed_guard(self):
        for guard in ("", self.guard.replace("status 0;", "status 125;"),
                      self.guard + "memory guard: stopping workload\n"):
            self.assertTrue(self.inspect(guard=guard)["problems"])

    def test_wrong_or_missing_promotion(self):
        for guard in (self.guard.replace("Full.vo", "Partial.vo"),
                      self.guard.split("\n", 1)[1], self.guard + self.guard):
            self.assertTrue(self.inspect(guard=guard)["problems"])


class ArtifactEvidenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / "run.log").write_text(RUN, encoding="utf-8")
        (self.root / "guard.log").write_text(
            f"checkpoint runner: atomically promoted {self.root / 'Full.vo'}\n"
            "memory guard: finished with status 0; cgroup peak=123 KiB\n",
            encoding="utf-8",
        )
        (self.root / "Full.vo").write_bytes(b"synthetic artifact, not a Rocq library")
        (self.root / "input").write_bytes(b"fixture")
        self.manifest = {
            "run_log": "run.log", "guard_log": "guard.log", "artifact": "Full.vo",
            "expected": EXPECTED,
            "sha256": {"input": hashlib.sha256(b"fixture").hexdigest()},
        }

    def check(self):
        path = self.root / "manifest.json"
        path.write_text(json.dumps(self.manifest), encoding="utf-8")
        return audit.audit(path)

    def test_matching_artifact_and_identity(self):
        result = self.check()
        self.assertTrue(result["run_evidence_complete"])
        self.assertEqual(result["artifact_sha256"],
                         hashlib.sha256((self.root / "Full.vo").read_bytes()).hexdigest())

    def test_changed_input(self):
        (self.root / "input").write_bytes(b"changed")
        self.assertFalse(self.check()["run_evidence_complete"])

    def test_missing_identities(self):
        self.manifest["sha256"] = {}
        self.assertFalse(self.check()["run_evidence_complete"])

    def test_missing_and_empty_artifact(self):
        (self.root / "Full.vo").unlink()
        self.assertFalse(self.check()["run_evidence_complete"])
        (self.root / "Full.vo").touch()
        self.assertFalse(self.check()["run_evidence_complete"])

    def test_incomplete_log_does_not_hash_large_files(self):
        (self.root / "guard.log").write_text("", encoding="utf-8")
        (self.root / "input").unlink()
        result = self.check()  # No attempt to open the now-missing input.
        self.assertFalse(result["run_evidence_complete"])


if __name__ == "__main__":
    unittest.main()
