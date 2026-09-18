"""Manual-only CLI policy; no real systemd, Codex or Rocq processes."""

from contextlib import ExitStack, redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cslib_loop
import mathlib_loop


class ManualLoopPolicyTests(unittest.TestCase):
    def test_start_and_worker_refuse_before_dispatch(self):
        for module in (cslib_loop, mathlib_loop):
            for command in (["start"], ["worker", "/nonexistent/loop"]):
                with self.subTest(module=module.__name__, command=command), ExitStack() as stack:
                    stack.enter_context(patch.object(sys, "argv", [module.__name__, *command]))
                    calls = [stack.enter_context(patch.object(module, "start")),
                             stack.enter_context(patch.object(cslib_loop, "Supervisor")),
                             stack.enter_context(patch.object(mathlib_loop, "MathlibSupervisor")),
                             stack.enter_context(patch.object(module.subprocess, "run")),
                             stack.enter_context(patch.object(module.subprocess, "check_output")),
                             stack.enter_context(patch.object(module.shutil, "which"))]
                    error = stack.enter_context(redirect_stderr(io.StringIO()))
                    self.assertEqual(module.main(), 2)
                    self.assertIn("Autonomy disabled", error.getvalue())
                    self.assertIn("python3 scripts/run_cslib_from_start.py", error.getvalue())
                    for call in calls:
                        call.assert_not_called()

    def test_status_is_available_without_archived_state(self):
        for module in (cslib_loop, mathlib_loop):
            with self.subTest(module=module.__name__), tempfile.TemporaryDirectory() as temp, \
                    patch.object(module, "STATE_ROOT", Path(temp)), \
                    patch.object(sys, "argv", [module.__name__, "status"]), \
                    patch.object(module.subprocess, "run") as run, \
                    redirect_stdout(io.StringIO()) as output:
                self.assertEqual(module.main(), 0)
                self.assertIn("manual runs start at line 1", output.getvalue())
                self.assertIn("No archived loop state", output.getvalue())
                run.assert_not_called()

    def test_existing_status_is_explicitly_archived(self):
        for module, library in ((cslib_loop, "cslib"), (mathlib_loop, "mathlib")):
            with self.subTest(module=module.__name__), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                directory = root / "example"
                directory.mkdir()
                (root / "latest").symlink_to(directory)
                (directory / "state.json").write_text(json.dumps({
                    "unit": f"rocq-{library}-loop-example.service", "phase": "paused",
                    "model": "historical", "reasoning": "xhigh", "repairs": 1,
                    "max_repairs": 3, "created": "historical",
                    "checkpoint_plan": str(root / "absent-plan.json"),
                }))
                with patch.object(module, "STATE_ROOT", root), \
                        patch.object(sys, "argv", [module.__name__, "status"]), \
                        redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(module.main(), 0)
                    self.assertIn("Autonomy disabled", output.getvalue())
                    self.assertIn("not the current manual run", output.getvalue())

    def test_pause_and_stop_remain_allowed_by_policy(self):
        for command in ("status", "pause", "stop"):
            with self.subTest(command=command):
                cslib_loop.check_manual_only_policy(command)


if __name__ == "__main__":
    unittest.main()
