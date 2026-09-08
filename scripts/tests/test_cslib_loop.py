"""Supervisor tests: fake compilation/Codex only; no model calls or Rocq jobs."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cslib_loop as loop


class LoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.attempt = self.root / "attempt.example"
        self.attempt.mkdir()
        self.log = self.root / "compile.log"
        self.log.write_text("Starting Complete15M\n")
        self.run_log = self.attempt / "Complete15M.run.log"
        self.run_log.write_text("Error at line 16372304 (for UInt32.example): #HINT_OPAQUE\nStack overflow.\n")
        self.state = {"unit": "rocq-cslib-loop-test.service", "model": loop.MODEL,
                      "phase": "starting", "repairs": 0, "max_repairs": 3,
                      "repair_seconds": 7200, "codex": "codex"}
        loop.atomic_json(self.root / "state.json", self.state)
        # Unit tests must not prepare real 22M-line generations when the live
        # importer differs from its historical checkpoint manifest.
        for module, name in ((loop.generations, "representation"), (loop.chunks, "manifest_entries")):
            patcher = patch.object(module, name, return_value={"plugin": "old"})
            patcher.start()
            self.addCleanup(patcher.stop)

    def supervisor(self):
        return loop.Supervisor(self.root)

    def test_exact_model_and_reasoning_for_new_and_resumed_turns(self):
        for session in (None, "specific-session"):
            cmd = loop.codex_command("codex", session, self.root / "reply.json")
            self.assertEqual(cmd[cmd.index("--model") + 1], "gpt-6-astra")
            self.assertIn('model_reasoning_effort="xhigh"', cmd)
            self.assertIn('sandbox_mode="workspace-write"', cmd)
            self.assertIn('approval_policy="never"', cmd)
            self.assertNotIn("--last", cmd)
            self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", cmd)
            if session:
                self.assertEqual(cmd[cmd.index("resume") + 1], session)

    def test_error_name_survives_a_giant_type_error(self):
        with self.run_log.open("a") as f:
            f.write("giant error\n" * 10000)
        report = loop.failure_report(self.attempt, self.log, 1)
        self.assertEqual(report["declaration"], "UInt32.example")
        self.assertEqual(report["line"], 16372304)
        self.assertLess(len(json.dumps(report)), 14000)

    def test_full_access_requires_an_explicit_option(self):
        normal = loop.codex_command("codex", None, self.root / "reply.json")
        full = loop.codex_command("codex", None, self.root / "reply.json", "full")
        self.assertIn('sandbox_mode="workspace-write"', normal)
        self.assertIn('sandbox_mode="danger-full-access"', full)
        self.assertIn('approval_policy="never"', full)

    def test_done_is_not_full_success(self):
        self.log.write_text("Done!\nPassed Complete15M\n")
        with self.assertRaises(loop.Paused):
            loop.verify_success(self.attempt, self.log)

    def test_success_requires_correct_artifacts(self):
        self.log.write_text("".join("Passed " + s + "\n" for s in loop.STAGES))
        for stage in loop.STAGES[2:]:
            (self.root / (stage + ".vo")).write_text(stage)
        (self.root / "Complete15M.seal").mkdir()
        manifest = self.attempt / "artifacts.sha256"
        manifest.write_text("".join(loop.digest(self.root / (s + ".vo")) + "  " +
                                   str(self.root / (s + ".vo")) + "\n" for s in loop.STAGES[2:]))
        with patch.object(loop, "RUN_ROOT", self.root):
            loop.verify_success(self.attempt, self.log)
            (self.root / "Complete15M.vo").write_text("corrupt")
            with self.assertRaises(subprocess.CalledProcessError):
                loop.verify_success(self.attempt, self.log)

    def test_waiting_uses_local_queries_only(self):
        info = {"LoadState": "loaded", "InvocationID": "id", "ActiveState": "active"}
        final = {**info, "ActiveState": "failed", "ExecMainCode": "1",
                 "ExecMainStatus": "1", "Result": "exit-code"}
        with patch.object(loop, "unit_info", side_effect=[info, info, final]), \
                patch.object(loop.time, "sleep") as sleep, \
                patch.object(loop, "codex_command") as codex:
            code = loop.wait_for_unit({"unit": "test", "invocation": "id"}, lambda: False)
        self.assertEqual(code, 1)
        self.assertEqual(sleep.call_count, 2)
        codex.assert_not_called()

    def test_restarted_service_is_not_adopted_silently(self):
        with patch.object(loop, "unit_info", return_value={"LoadState": "loaded", "InvocationID": "new"}):
            with self.assertRaises(loop.Paused):
                loop.wait_for_unit({"unit": "test", "invocation": "old"}, lambda: False)

    def test_signal_or_oom_never_triggers_repair(self):
        info = {"LoadState": "loaded", "InvocationID": "id", "ActiveState": "failed",
                "ExecMainCode": "2", "ExecMainStatus": "9", "Result": "oom-kill"}
        with patch.object(loop, "unit_info", return_value=info):
            with self.assertRaises(loop.Paused):
                loop.wait_for_unit({"unit": "test", "invocation": "id"}, lambda: False)

    def test_pause_does_not_touch_adopted_service(self):
        with patch.object(loop, "unit_info") as info:
            with self.assertRaises(loop.Paused):
                loop.wait_for_unit({}, lambda: True)
            info.assert_not_called()

    def test_success_invokes_no_model(self):
        worker = self.supervisor()
        worker.compile = Mock(return_value=(0, self.attempt, self.log))
        worker.repair = Mock()
        with patch.object(loop, "verify_success") as verify:
            self.assertEqual(worker.run(), 0)
        verify.assert_called_once()
        worker.repair.assert_not_called()
        self.assertEqual(worker.state["phase"], "complete")

    def test_resource_and_unknown_failures_pause_without_codex(self):
        for code in (75, 78, 124, 125, 137, 143, -15):
            worker = self.supervisor()
            worker.compile = Mock(return_value=(code, self.attempt, self.log))
            worker.repair = Mock()
            self.assertEqual(worker.run(), 2)
            worker.repair.assert_not_called()
        self.run_log.write_text("Some infrastructure failure\n")
        worker = self.supervisor()
        worker.compile = Mock(return_value=(1, self.attempt, self.log))
        worker.repair = Mock()
        self.assertEqual(worker.run(), 2)
        worker.repair.assert_not_called()

    def test_fail_repair_resume_success_order(self):
        worker = self.supervisor()
        events = []
        def compile_next():
            events.append("compile")
            return (1 if len(events) == 1 else 0, self.attempt, self.log)
        worker.compile = compile_next
        worker.repair = lambda report: events.append("repair")
        with patch.object(loop, "verify_success"):
            self.assertEqual(worker.run(), 0)
        self.assertEqual(events, ["compile", "repair", "compile"])

    def test_same_declaration_stops_after_one_unsuccessful_repair(self):
        worker = self.supervisor()
        worker.compile = Mock(return_value=(1, self.attempt, self.log))
        worker.repair = Mock()
        self.assertEqual(worker.run(), 2)
        self.assertEqual(worker.compile.call_count, 2)
        worker.repair.assert_called_once()

    def test_zero_budget_compiles_but_never_invokes_codex(self):
        worker = self.supervisor()
        worker.state["max_repairs"] = 0
        worker.compile = Mock(return_value=(1, self.attempt, self.log))
        worker.repair = Mock()
        self.assertEqual(worker.run(), 2)
        worker.repair.assert_not_called()

    def test_pause_before_launch(self):
        (self.root / "PAUSE").touch()
        worker = self.supervisor()
        worker.compile = Mock()
        self.assertEqual(worker.run(), 2)
        worker.compile.assert_not_called()

    def result_files(self, result=None):
        directory = self.root / "repair-01"
        directory.mkdir()
        loop.atomic_json(directory / "result.json", result or {
            "status": "ready", "summary": "Fixed", "tests": ["target: pass"],
            "checkpoint_action": "reuse", "foundation": ""})
        (directory / "events.jsonl").write_text(
            '{"type":"thread.started","thread_id":"session-id"}\n'
            '{"type":"turn.completed","usage":{"output_tokens":42}}\n')
        return directory

    def test_structured_result_and_usage(self):
        session, usage, result = loop.read_codex_result(self.result_files())
        self.assertEqual(session, "session-id")
        self.assertEqual(usage[0]["output_tokens"], 42)
        self.assertEqual(result["status"], "ready")

    def test_no_completed_turn_is_not_a_success(self):
        directory = self.result_files()
        (directory / "events.jsonl").write_text('{"type":"turn.failed"}\n')
        with self.assertRaises(loop.Paused):
            loop.read_codex_result(directory)

    def test_ready_requires_evidence(self):
        directory = self.result_files({"status": "ready", "summary": "trust me", "tests": []})
        with self.assertRaises(loop.Paused):
            loop.read_codex_result(directory)

    def test_protected_input_changes_stop_continuation(self):
        before = {str(self.run_log): loop.digest(self.run_log)}
        loop.check_protected(before)
        self.run_log.write_text("changed")
        with self.assertRaises(loop.Paused):
            loop.check_protected(before)

    def test_agent_failure_does_not_retry_or_validate(self):
        worker = self.supervisor()
        worker.service = Mock(return_value=1)
        with patch.object(loop, "protected_inputs", return_value={}):
            with self.assertRaises(loop.Paused):
                worker.repair_locked({"declaration": "example"})
        worker.service.assert_called_once()

    def test_ready_is_validated_before_resuming(self):
        worker = self.supervisor()
        worker.service = Mock(side_effect=[0, 1])
        with patch.object(loop, "protected_inputs", return_value={}), \
                patch.object(loop, "read_codex_result", return_value=("id", [], {
                    "status": "ready", "summary": "fixed", "tests": ["target passed"]})):
            with self.assertRaisesRegex(loop.Paused, "validation failed"):
                worker.repair_locked({"declaration": "example"})
        self.assertEqual(worker.service.call_count, 2)

    def test_restart_result_keeps_structured_contract(self):
        result = {"status": "ready", "summary": "source definition preserved", "tests": ["original proof passes"],
                  "checkpoint_action": "restart", "foundation": "/example/Lean.vo"}
        self.assertEqual(loop.read_codex_result(self.result_files(result))[2], result)

    def test_missing_checkpoint_decision_is_rejected(self):
        result = {"status": "ready", "summary": "fixed", "tests": ["passed"]}
        with self.assertRaises(loop.Paused):
            loop.read_codex_result(self.result_files(result))

    def test_pending_repair_does_not_replay_full_failure(self):
        worker = self.supervisor()
        worker.state["pending_failure"] = {"declaration": "Nat.beq.eq_def"}
        worker.repair = Mock(side_effect=loop.Paused("stop after handoff"))
        worker.compile = Mock()
        self.assertEqual(worker.run(), 2)
        worker.repair.assert_called_once()
        worker.compile.assert_not_called()

    def test_pending_validation_never_calls_the_model_or_resets_the_budget(self):
        worker = self.supervisor()
        worker.state.update(pending_validation={"candidate": "reviewed"}, repairs=1)
        order = []
        worker.retry_validation = lambda handoff: order.append("validate")
        worker.compile = lambda: (order.append("compile") or (0, self.attempt, self.log))
        with patch.object(loop, "codex_command") as codex, patch.object(loop, "verify_success"):
            self.assertEqual(worker.run(), 0)
        codex.assert_not_called()
        self.assertEqual(order, ["validate", "compile"])
        self.assertEqual(worker.state["repairs"], 1)

    def test_failed_local_validation_prevents_compilation(self):
        worker = self.supervisor()
        worker.state["pending_validation"] = {"candidate": "reviewed"}
        worker.retry_validation = Mock(side_effect=loop.Paused("validation failed"))
        worker.compile = Mock()
        with patch.object(loop, "codex_command") as codex:
            self.assertEqual(worker.run(), 2)
        codex.assert_not_called()
        worker.compile.assert_not_called()

    def test_operator_validation_preserves_blocked_result_and_pins_candidate(self):
        result = {"status": "blocked", "summary": "harness source missing", "tests": ["target passed"],
                  "checkpoint_action": "restart", "foundation": ""}
        directory = self.result_files(result)
        previous = {**self.state, "phase": "paused", "requires_validation": True,
                    "repair_directory": str(directory), "last_result": result}
        evidence = (directory / "result.json").read_bytes()
        handoff = loop.validation_handoff(previous, self.root / "state.json")
        self.assertEqual(handoff["result"]["status"], "blocked")
        self.assertEqual((directory / "result.json").read_bytes(), evidence)
        self.assertEqual(handoff["inputs"][str(loop.chunks.WORKER)], loop.digest(loop.chunks.WORKER))
        self.assertIn(str(directory / "result.json"), handoff["inputs"])

    def test_changed_candidate_is_refused_before_validation(self):
        worker = self.supervisor()
        worker.validate_repair = Mock()
        handoff = {"inputs": {str(self.run_log): "wrong hash"}}
        with patch.object(loop, "RUN_ROOT", self.root), \
                patch.object(loop.subprocess, "check_output", return_value=""):
            with self.assertRaises(loop.Paused):
                worker.retry_validation(handoff)
        worker.validate_repair.assert_not_called()

    def test_local_validation_runs_the_gate_without_a_repair_service(self):
        worker = self.supervisor()
        worker.state["repairs"] = 1
        worker.service = Mock(return_value=0)
        result = {"status": "blocked", "checkpoint_action": "restart", "foundation": ""}
        new_plan = self.root / "new-plan.json"
        loop.atomic_json(new_plan, {"toolchain": {"path": "test"}})
        handoff = {"inputs": {}, "foundation": str(loop.chunks.FOUNDATION / "Lean.vo"), "result": result}
        with patch.object(loop, "RUN_ROOT", self.root), \
                patch.object(loop.subprocess, "check_output", return_value=""), \
                patch.object(loop, "protected_inputs", return_value={}), \
                patch.object(loop.generations, "create", return_value=(new_plan, self.root / "smoke.json")), \
                patch.object(loop, "codex_command") as codex:
            worker.retry_validation(handoff)
        codex.assert_not_called()
        worker.service.assert_called_once()
        self.assertIn("checkpoint_generation.py", " ".join(worker.service.call_args.args[1]))
        self.assertEqual(worker.state["repairs"], 1)
        self.assertFalse(worker.state["requires_validation"])

    def test_representation_restart_is_local_after_one_agent_call(self):
        worker = self.supervisor()
        worker.service = Mock(return_value=0)
        new_plan = self.root / "new-plan.json"
        loop.atomic_json(new_plan, {"toolchain": {"path": "test"}})
        result = {"status": "ready", "summary": "fixed", "tests": ["original proof passes"],
                  "checkpoint_action": "restart", "foundation": ""}
        with patch.object(loop, "protected_inputs", return_value={}), \
                patch.object(loop, "read_codex_result", return_value=("same-session", [], result)), \
                patch.object(loop.generations, "create", return_value=(new_plan, self.root / "smoke.json")) as create:
            worker.repair_locked({"declaration": "Nat.beq.eq_def"})
        create.assert_called_once()
        self.assertEqual(worker.service.call_count, 2)
        self.assertIn("repair-01", worker.service.call_args_list[0].args[0])
        self.assertIn("checkpoint_generation.py", " ".join(worker.service.call_args_list[1].args[1]))
        self.assertNotIn("codex", " ".join(worker.service.call_args_list[1].args[1]))
        self.assertEqual(worker.state["checkpoint_plan"], str(new_plan))
        self.assertFalse(worker.state["requires_validation"])

    def test_detected_representation_change_forces_restart_even_if_agent_says_reuse(self):
        worker = self.supervisor()
        worker.service = Mock(return_value=0)
        result = {"status": "ready", "summary": "fixed", "tests": ["passed"], "checkpoint_action": "reuse", "foundation": ""}
        with patch.object(loop, "protected_inputs", return_value={}), \
                patch.object(loop, "read_codex_result", return_value=("session", [], result)), \
                patch.object(loop.chunks, "manifest_entries", return_value={"plugin": "old"}), \
                patch.object(loop.generations, "representation", side_effect=[{"plugin": "old"}, {"plugin": "new"}]), \
                patch.object(loop.generations, "create", side_effect=loop.Paused("restart selected")) as create:
            with self.assertRaisesRegex(loop.Paused, "restart selected"):
                worker.repair_locked({"declaration": "example"})
        create.assert_called_once()
        self.assertEqual(worker.service.call_count, 1)

    def test_agent_can_run_regressions_but_cannot_monitor_full_pass(self):
        prompt = (loop.SUPPORT / "repair-prompt.md").read_text()
        self.assertIn("may run broader regression suites", prompt)
        self.assertIn("Do not launch, poll or watch long-running full-library compilation", prompt)

    def test_lock_rejects_a_second_supervisor(self):
        with patch.object(loop, "STATE_ROOT", self.root), loop.loop_lock():
            with self.assertRaises(loop.Paused), loop.loop_lock():
                self.fail("Acquired an already held lock")

    def test_repair_refuses_a_live_rocq_worker(self):
        worker = self.supervisor()
        worker.repair_locked = Mock()
        with patch.object(loop, "RUN_ROOT", self.root), \
                patch.object(loop.subprocess, "check_output", return_value="bash\nrocqworker\n"):
            with self.assertRaisesRegex(loop.Paused, "worker is still active"):
                worker.repair({})
        worker.repair_locked.assert_not_called()

    def test_repair_excludes_a_manual_launcher(self):
        worker = self.supervisor()
        worker.repair_locked = Mock()
        with patch.object(loop, "RUN_ROOT", self.root), (self.root / "launcher.lock").open("a") as lock:
            loop.fcntl.flock(lock, loop.fcntl.LOCK_EX | loop.fcntl.LOCK_NB)
            with self.assertRaisesRegex(loop.Paused, "launcher is still active"):
                worker.repair({})
        worker.repair_locked.assert_not_called()

    def test_child_service_is_bounded_and_bound_to_its_owner(self):
        worker = self.supervisor()
        worker.record = Mock()
        with patch.object(loop.subprocess, "run", return_value=Mock(returncode=0)) as run:
            self.assertEqual(worker.service("test", ["/usr/bin/true"], self.root, 60), 0)
        cmd = run.call_args.args[0]
        self.assertIn("--wait", cmd)
        self.assertIn("--property=RuntimeMaxSec=60", cmd)
        self.assertIn("--property=BindsTo=" + self.state["unit"], cmd)
        self.assertIn("--property=MemoryMax=2G", cmd)
        self.assertIn("--property=KillMode=control-group", cmd)

    def test_adoption_rejects_checkpoint_only_service(self):
        info = {"LoadState": "loaded", "InvocationID": "id",
                "ExecStart": str(loop.LAUNCHER) + " --run --checkpoint-only"}
        with patch.object(loop, "unit_info", return_value=info):
            with self.assertRaises(loop.Paused):
                loop.adopted_run("rocq-cslib-15m-20260908T003004523686560.service")

    def test_chunked_failure_reaches_the_repair_phase(self):
        loop.atomic_json(self.attempt / "status.json", {
            "format": "chunked-import-v1", "plan": str(loop.CHUNK_PLAN),
            "phase": "importing", "module": "CslibTo17001015"})
        (self.attempt / "CslibTo17001015.run.log").write_text(self.run_log.read_text())
        worker = self.supervisor()
        worker.compile = Mock(return_value=(1, self.attempt, self.log))
        worker.repair = Mock(side_effect=loop.Paused("test stops at repair"))
        self.assertEqual(worker.run(), 2)
        report = worker.repair.call_args.args[0]
        self.assertEqual(report["checkpoint_phase"], "importing")
        self.assertEqual(report["declaration"], "UInt32.example")

    def test_chunk_reload_failure_does_not_launch_a_repair(self):
        loop.atomic_json(self.attempt / "status.json", {
            "format": "chunked-import-v1", "plan": str(loop.CHUNK_PLAN),
            "phase": "reloading", "module": "CslibTo17001015Reload"})
        (self.attempt / "CslibTo17001015Reload.run.log").write_text(self.run_log.read_text())
        worker = self.supervisor()
        worker.compile = Mock(return_value=(1, self.attempt, self.log))
        worker.repair = Mock()
        self.assertEqual(worker.run(), 2)
        worker.repair.assert_not_called()

    def test_chunk_success_requires_plan_verification(self):
        loop.atomic_json(self.attempt / "status.json", {
            "format": "chunked-import-v1", "plan": str(loop.CHUNK_PLAN), "phase": "complete"})
        with patch.object(loop.subprocess, "run") as verify:
            loop.verify_success(self.attempt, self.log)
        self.assertIn("verify", verify.call_args.args[0])
        self.assertTrue(verify.call_args.kwargs["check"])

    def test_failed_smoke_prevents_full_chunked_compilation(self):
        worker = self.supervisor()
        with patch.object(loop.subprocess, "run", return_value=Mock(returncode=1)) as run:
            with self.assertRaisesRegex(loop.Paused, "smoke test failed"):
                worker.compile()
        run.assert_called_once()

    def test_chunked_compile_is_sequential_and_uses_the_new_runner(self):
        worker = self.supervisor()
        def fake_run(cmd, **kwargs):
            attempt = Path(cmd[cmd.index("--attempt") + 1])
            attempt.mkdir()
            loop.atomic_json(attempt / "status.json", {"phase": "importing"})
            return Mock(returncode=0)
        with patch.object(loop, "RUN_ROOT", self.root), \
                patch.object(loop.subprocess, "run", side_effect=fake_run) as run:
            code, attempt, _ = worker.compile()
        self.assertEqual(code, 0)
        self.assertEqual(run.call_count, 2)
        self.assertIn(str(loop.SMOKE_PLAN), run.call_args_list[0].args[0])
        self.assertIn(str(loop.CHUNK_PLAN), run.call_args_list[1].args[0])
        self.assertEqual((self.root / "latest").resolve(), attempt)


@unittest.skipUnless(os.environ.get("CSLIB_LOOP_SYSTEMD_TEST") == "1", "Opt-in local systemd smoke test")
class SystemdSmokeTests(unittest.TestCase):
    def test_service_handoff_and_exit_status(self):
        """Real lightweight services, but no Codex, guard scope or Rocq process."""
        unit = "rocq-cslib-loop-smoke-" + str(os.getpid()) + ".service"
        with tempfile.TemporaryDirectory(prefix="cslib-loop-smoke-") as temp:
            directory = Path(temp)
            loop.atomic_json(directory / "state.json", {"unit": unit, "phase": "testing"})
            code = (
                "import sys; from pathlib import Path; "
                "sys.path.insert(0, sys.argv[1]); import cslib_loop as m; "
                "d=Path(sys.argv[2]); s=m.Supervisor(d); "
                "assert s.service('cat', ['/usr/bin/cat'], d, 60, 'handoff verified') == 0; "
                "assert (d/'events.jsonl').read_text() == 'handoff verified'; "
                "assert s.service('false', ['/usr/bin/false'], d, 60) != 0"
            )
            result = subprocess.run([
                "systemd-run", "--user", "--wait", "--pipe", "--collect", "--unit=" + unit,
                "--property=RuntimeMaxSec=30", sys.executable, "-c", code,
                str(loop.ROOT / "scripts"), str(directory)], capture_output=True, text=True, timeout=45)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
