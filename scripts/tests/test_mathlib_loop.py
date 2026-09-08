"""Mathlib handoff tests; no model requests, exports, or Rocq workers."""

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mathlib_loop as loop


class MathlibLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = {"unit": "rocq-mathlib-loop-test.service", "phase": "starting", "prepared": False,
                      "model": "gpt-6-astra", "reasoning": "xhigh", "repair_access": "full",
                      "repairs": 0, "max_repairs": 3, "repair_seconds": 7200, "codex": "codex",
                      "checkpoint_plan": str(self.root / "plan.json"), "smoke_plan": str(self.root / "smoke.json")}
        loop.shared.atomic_json(self.root / "state.json", self.state)

    def supervisor(self):
        return loop.MathlibSupervisor(self.root)

    def test_waiting_on_active_cslib_does_not_launch_or_lock_shared_worker(self):
        worker = self.supervisor()
        with patch.object(loop, "cslib_candidate", return_value=(self.root, {"phase": "repairing"})), \
                patch.object(loop.time, "sleep", side_effect=KeyboardInterrupt), \
                patch.object(loop.shared, "loop_lock") as lock, \
                patch.object(worker, "prepare") as prepare, patch.object(worker, "service") as service:
            self.assertEqual(worker.run_when_ready(), 2)
        lock.assert_not_called()
        prepare.assert_not_called()
        service.assert_not_called()

    def test_paused_cslib_is_waiting_not_a_mathlib_repair_trigger(self):
        worker = self.supervisor()
        with patch.object(loop, "cslib_candidate", return_value=(self.root, {"phase": "paused", "reason": "needs fix"})), \
                patch.object(loop.time, "sleep", side_effect=KeyboardInterrupt), \
                patch.object(worker, "repair") as repair:
            worker.run_when_ready()
        repair.assert_not_called()

    def test_pause_while_waiting_never_touches_cslib(self):
        worker = self.supervisor()
        (self.root / "PAUSE").touch()
        with patch.object(loop, "cslib_candidate") as candidate, patch.object(loop.subprocess, "run") as run:
            self.assertEqual(worker.run_when_ready(), 2)
        candidate.assert_not_called()
        run.assert_not_called()

    def test_verified_cslib_precedes_preparation_and_mathlib_run(self):
        worker = self.supervisor()
        events = []
        state = {"phase": "complete", "unit": "cslib.service"}
        with patch.object(loop, "cslib_candidate", return_value=(self.root, state)), \
                patch.object(loop.shared, "unit_info", return_value={"ActiveState": "inactive"}), \
                patch.object(loop.shared, "loop_lock"), \
                patch.object(loop, "verify_cslib", side_effect=lambda *a: events.append("verify") or self.root / "Lean.vo"), \
                patch.object(worker, "prepare", side_effect=lambda *a: events.append("prepare")), \
                patch.object(loop.shared.Supervisor, "run", side_effect=lambda: events.append("run") or 0):
            self.assertEqual(worker.run_when_ready(), 0)
        self.assertEqual(events, ["verify", "prepare", "run"])

    def test_invalid_completion_never_starts_mathlib(self):
        worker = self.supervisor()
        with patch.object(loop, "cslib_candidate", return_value=(self.root, {"phase": "complete", "unit": "cslib.service"})), \
                patch.object(loop.shared, "unit_info", return_value={"ActiveState": "inactive"}), \
                patch.object(loop.shared, "loop_lock"), \
                patch.object(loop, "verify_cslib", side_effect=loop.shared.Paused("seal mismatch")), \
                patch.object(worker, "prepare") as prepare:
            self.assertEqual(worker.run_when_ready(), 2)
        prepare.assert_not_called()

    def test_existing_mathlib_chain_resumes_without_old_cslib_worker_check(self):
        worker = self.supervisor()
        worker.state["prepared"] = True
        with patch.object(loop, "cslib_candidate", return_value=(self.root, {"phase": "complete"})), \
                patch.object(loop.shared, "loop_lock"), patch.object(loop, "verify_cslib") as verify, \
                patch.object(loop.shared.Supervisor, "run", return_value=0):
            self.assertEqual(worker.run_when_ready(), 0)
        verify.assert_not_called()

    def test_repair_prompt_is_mathlib_specific_but_keeps_regression_permission(self):
        worker = self.supervisor()
        directory = self.root / "repair"
        directory.mkdir()
        loop.shared.atomic_json(directory / "failure.json", {"declaration": "Mathlib.example"})
        with patch.object(worker, "foundation", return_value=self.root / "Lean.vo"), \
                patch.object(loop.shared.Supervisor, "service", return_value=0) as service:
            worker.service("repair-01", ["codex"], directory, 7200, "OLD CSLIB PROMPT")
        prompt = service.call_args.args[-1]
        self.assertNotIn("OLD CSLIB PROMPT", prompt)
        self.assertIn("Mathlib.example", prompt)
        self.assertIn("broader regressions as needed", prompt)
        self.assertIn("Do not launch or monitor full-library", prompt)

    def test_validation_does_not_get_an_agent_prompt(self):
        worker = self.supervisor()
        with patch.object(loop.shared.Supervisor, "service", return_value=0) as service:
            worker.service("validate-01", ["python3", "regressions.py"], self.root, 3600)
        self.assertIsNone(service.call_args.args[-1])

    def test_compile_checks_smoke_before_full_without_touching_cslib_logs(self):
        worker = self.supervisor()
        with patch.object(worker, "mathlib_smoke", return_value=Path(self.state["smoke_plan"])), \
                patch.object(worker, "run_plan", return_value=(0, self.root, self.root / "run.log")) as run:
            worker.compile()
        self.assertEqual([c.args[0] for c in run.call_args_list],
                         [Path(self.state["smoke_plan"]), Path(self.state["checkpoint_plan"])])
        self.assertFalse((loop.shared.RUN_ROOT / (".latest-" + self.root.name)).exists())

    def test_smoke_failure_prevents_full_compilation(self):
        worker = self.supervisor()
        with patch.object(worker, "mathlib_smoke", return_value=Path(self.state["smoke_plan"])), \
                patch.object(worker, "run_plan", return_value=(1, self.root, self.root / "run.log")) as run:
            self.assertEqual(worker.compile()[0], 1)
        run.assert_called_once()

    def test_mathlib_completion_does_not_claim_mathlib_is_next(self):
        worker = self.supervisor()
        worker.record("complete", next_target={"library": "Mathlib"})
        self.assertIsNone(worker.state["next_target"])
        self.assertIn("Mathlib", worker.state["reason"])

    def test_queue_lock_prevents_duplicate_mathlib_queues(self):
        with patch.object(loop, "STATE_ROOT", self.root), loop.queue_lock():
            with self.assertRaises(loop.shared.Paused), loop.queue_lock():
                self.fail("Acquired an already-held queue lock")

    def test_cslib_predecessor_identity_is_checked(self):
        cslib = self.root / "cslib"
        directory = cslib / "stamp"
        directory.mkdir(parents=True)
        (cslib / "latest").symlink_to(directory)
        loop.shared.atomic_json(directory / "state.json", {"unit": "unrelated.service"})
        with patch.object(loop.shared, "STATE_ROOT", cslib):
            with self.assertRaises(loop.shared.Paused):
                loop.cslib_candidate()

    def test_exact_astra_model_and_effort_are_shared(self):
        command = loop.shared.codex_command("codex", None, self.root / "result.json", "full")
        self.assertIn("gpt-6-astra", command)
        self.assertIn('model_reasoning_effort="xhigh"', command)
        self.assertNotIn("--last", command)


if __name__ == "__main__":
    unittest.main()
