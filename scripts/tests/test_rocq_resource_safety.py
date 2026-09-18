"""Dispatch/cleanup tests only: no real guard, cgroup, make, or Rocq is run."""

from __future__ import annotations

import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / "checkers/rocq-lean-import/scripts"
SPEC = importlib.util.spec_from_file_location(
    "frontier", ROOT / "scripts/run_rocq_frontier.py"
)
assert SPEC is not None and SPEC.loader is not None
frontier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(frontier)


class CheckerLaunchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.scripts = self.root / "scripts"
        self.scripts.mkdir()
        for name in ("run.sh", "run-internal.sh", "build.sh", "build-internal.sh"):
            shutil.copy2(CHECKER / name, self.scripts / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.input = self.root / "input.lean-export"
        self.input.write_text("#fixture\n", encoding="utf-8")
        self.importer = self.root / "importer"
        (self.importer / "src").mkdir(parents=True)
        for name in ("Lean.vo", "lean_import.cmxs"):
            (self.importer / "src" / name).touch()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("ROCQLKA_", "ROCQ_", "_ROCQ_"))
        }
        self.env.update({
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "FAKE_CALLS": str(self.calls),
            "FAKE_PID": str(self.root / "worker.pid"),
            "ROCQLKA_ROCQ": str(self.bin / "rocq"),
            "ROCQLKA_IMPORTER_ROOT": str(self.importer),
            "ROCQLKA_TMP_ROOT": str(self.root / "tmp"),
            "ROCQLKA_KEEP_TMP": "0",
            "ROCQLKA_ANNOUNCE_TTY": "0",
            "ROCQLKA_PROGRESS_POLL": "1",
        })
        self.executable(self.scripts / "run-memory-guarded.sh", """#!/bin/bash
printf 'guard\\n' >> "$FAKE_CALLS"
if [[ ${FAKE_GUARD_STATUS:-0} != 0 ]]; then exit "$FAKE_GUARD_STATUS"; fi
exec "$@"
""")
        self.executable(self.bin / "make", """#!/bin/bash
printf 'make %s\\n' "$*" >> "$FAKE_CALLS"
exit "${FAKE_MAKE_STATUS:-0}"
""")
        self.executable(self.bin / "git", "#!/bin/bash\nexit 1\n")
        self.executable(self.bin / "rocq", """#!/bin/bash
if [[ $1 == --version ]]; then
  printf 'version\\n' >> "$FAKE_CALLS"
  printf 'Rocq 9.3 mock\\n'
  exit 0
fi
printf 'compile\\n' >> "$FAKE_CALLS"
if [[ ${FAKE_ROCQ_WAIT:-0} == 1 ]]; then
  printf '%s\\n' "$$" > "$FAKE_PID"
  trap 'exit 0' TERM
  while :; do sleep 0.1; done
fi
exit "${FAKE_ROCQ_STATUS:-0}"
""")
        self.executable(self.scripts / "ndjson_to_lean_export.py", """#!/usr/bin/python3
import os
import sys
with open(os.environ['FAKE_CALLS'], 'a') as calls:
    calls.write('convert\\n')
with open(sys.argv[2], 'w') as output:
    output.write('#fixture\\n')
""")

    @staticmethod
    def executable(path: Path, source: str) -> None:
        path.write_text(source, encoding="utf-8")
        path.chmod(0o755)

    def run_script(self, name: str, **environment: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [str(self.scripts / name), str(self.input)],
            env={**self.env, **environment},
            text=True, capture_output=True, timeout=10,
        )

    def test_build_is_guarded_and_serial(self) -> None:
        result = self.run_script("build.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(calls[0], "guard")
        self.assertIn("-j1", calls[1])
        self.assertEqual(calls[2:], ["compile"])

    def test_build_rejects_parallel_jobs_before_launch(self) -> None:
        result = self.run_script("build.sh", ROCQLKA_BUILD_JOBS="2")
        self.assertEqual(result.returncode, 3)
        self.assertIn("must be 1", result.stderr)
        self.assertFalse(self.calls.exists())

    def test_guard_refusal_statuses_are_preserved(self) -> None:
        for name in ("run.sh", "build.sh"):
            for status in (75, 78, 125, 137):
                with self.subTest(name=name, status=status):
                    result = self.run_script(name, FAKE_GUARD_STATUS=str(status))
                    self.assertEqual(result.returncode, status)
        self.assertEqual(self.calls.read_text().splitlines(), ["guard"] * 8)

    def test_make_and_load_failures_are_preserved(self) -> None:
        result = self.run_script("build.sh", FAKE_MAKE_STATUS="137")
        self.assertEqual(result.returncode, 137)
        self.assertNotIn("compile", self.calls.read_text())
        result = self.run_script("build.sh", FAKE_ROCQ_STATUS="139")
        self.assertEqual(result.returncode, 139)

    def test_checker_child_status_is_preserved(self) -> None:
        result = self.run_script("run.sh", FAKE_ROCQ_STATUS="137")
        self.assertEqual(result.returncode, 137, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["guard", "version", "compile"])

    def test_adapter_runs_inside_same_guard(self) -> None:
        self.input.write_text("{}\n", encoding="utf-8")
        result = self.run_script("run.sh", ROCQLKA_LEGACY_CACHE="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls.read_text().splitlines(), ["guard", "version", "convert", "compile"]
        )

    def test_generated_import_does_not_silently_skip_quotients(self) -> None:
        result = self.run_script("run.sh", ROCQLKA_KEEP_TMP="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        sources = list((self.root / "tmp").glob("*/Check.v"))
        self.assertEqual(len(sources), 1)
        source = sources[0].read_text()
        self.assertIn('Set Lean Error Mode "Fail".', source)
        self.assertIn("Unset Lean Skip Missing Quotient.", source)

    @unittest.skipUnless(shutil.which("setsid"), "requires setsid for the detached fake child")
    def test_signal_stops_detached_fake_child(self) -> None:
        process = subprocess.Popen(
            [str(self.scripts / "run.sh"), str(self.input)],
            env={**self.env, "FAKE_ROCQ_WAIT": "1"},
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        fake_pid = None
        try:
            pid_file = Path(self.env["FAKE_PID"])
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not pid_file.exists():
                self.assertIsNone(process.poll())
                time.sleep(0.02)
            self.assertTrue(pid_file.exists(), "fake worker did not start")
            fake_pid = int(pid_file.read_text())
            process.terminate()
            _, stderr = process.communicate(timeout=8)
            self.assertEqual(process.returncode, 143, stderr)
            with self.assertRaises(ProcessLookupError):
                os.kill(fake_pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)
            if fake_pid is not None:
                try:
                    os.killpg(fake_pid, 9)
                except ProcessLookupError:
                    pass


class FakeProcess:
    def __init__(self, output: str = "", status: int = 0):
        self.stdout = io.StringIO(output)
        self.output = output
        self.returncode = status

    def communicate(self):
        return self.output, None

    def wait(self, timeout=None):
        return self.returncode


class FrontierLaunchTests(unittest.TestCase):
    @contextlib.contextmanager
    def mocked_frontier(self, *, rocq: str = "rocq"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "input.lean-export"
            source.write_text("#fixture\n", encoding="utf-8")
            importer = root / "importer"
            (importer / ".git").mkdir(parents=True)
            args = argparse.Namespace(
                input=source, importer_root=importer, opam_switch="mock",
                expected_rocq="9.3", from_line=None, until_line=None,
                progress_timeout=10, jobs=1, no_build=True,
                state=root / "state.json", log_dir=root / "logs",
            )
            commands, environments = [], []

            def popen(command, **kwargs):
                commands.append(command)
                if command[-1] == "--version":
                    return FakeProcess("Rocq 9.3 mock\n")
                self.assertEqual(command[:2], ["/usr/bin/time", "-v"])
                environments.append(kwargs["env"])
                return FakeProcess("line 1: mock\n")

            with patch.object(frontier, "parse_args", return_value=args), \
                 patch.object(frontier, "run_text", return_value="mock-commit"), \
                 patch.object(frontier.subprocess, "Popen", side_effect=popen), \
                 patch.dict(os.environ, {"ROCQLKA_ROCQ": rocq}), \
                 contextlib.redirect_stdout(io.StringIO()):
                yield args, commands, environments

    def test_selected_rocq_matches_probe_compilation_and_provenance(self) -> None:
        for selected, expected in (
            ("/mock/bin/selected-rocq", "/mock/bin/selected-rocq"),
            ("custom-rocq", "custom-rocq"),
            ("relative/bin/rocq", str(Path.cwd() / "relative/bin/rocq")),
            ("link/../rocq", str(Path.cwd() / "link/../rocq")),
            ("/mock/link/../rocq", "/mock/link/../rocq"),
            ("", "rocq"),
        ):
            with self.subTest(selected=selected), \
                 self.mocked_frontier(rocq=selected) as (args, commands, environments):
                self.assertEqual(frontier.main(), 0)
                command = ["opam", "exec", "--switch=mock", "--", expected]
                self.assertEqual(Path(commands[0][0]).name, "run-memory-guarded.sh")
                self.assertEqual(commands[0][1:], command + ["--version"])
                self.assertEqual(environments[0]["ROCQLKA_ROCQ"], expected)
                record = json.loads(args.state.read_text())["latest"]
                self.assertEqual(record["rocq"]["command"], command)

    def test_history_keeps_input_identity_per_run(self) -> None:
        with self.mocked_frontier() as (args, _, _):
            self.assertEqual(frontier.main(), 0)
            original = json.loads(args.state.read_text())["input"]
            args.input = args.input.with_name("different.lean-export")
            args.input.write_text("#changed\n", encoding="utf-8")
            self.assertEqual(frontier.main(), 0)
            state = json.loads(args.state.read_text())
            self.assertEqual(len(state["runs"]), 2)
            self.assertEqual(state["runs"][0]["input"], original)
            self.assertEqual(state["runs"][1]["input"], state["input"])
            self.assertNotEqual(original["path"], state["input"]["path"])
            self.assertNotEqual(original["sha256"], state["input"]["sha256"])

    def test_fast_runs_keep_distinct_logs(self) -> None:
        with self.mocked_frontier() as (args, _, _), \
             patch.object(frontier.time, "strftime", return_value="same-second"):
            self.assertEqual(frontier.main(), 0)
            self.assertEqual(frontier.main(), 0)
            runs = json.loads(args.state.read_text())["runs"]
            self.assertNotEqual(runs[0]["log"], runs[1]["log"])
            self.assertTrue(all(Path(run["log"]).is_file() for run in runs))

    def test_changed_input_is_rehashed_even_with_same_size_and_mtime(self) -> None:
        with self.mocked_frontier() as (args, _, _):
            self.assertEqual(frontier.main(), 0)
            original = json.loads(args.state.read_text())["input"]
            stat = args.input.stat()
            args.input.write_text("#changed\n", encoding="utf-8")
            os.utime(args.input, ns=(stat.st_atime_ns, stat.st_mtime_ns))
            self.assertEqual(frontier.main(), 0)
            current = json.loads(args.state.read_text())["input"]
            for key in ("path", "size", "mtime_ns"):
                self.assertEqual(current[key], original[key])
            self.assertNotEqual(current["sha256"], original["sha256"])
            self.assertEqual(current["sha256"], frontier.sha256_file(args.input))

    def test_next_entry_recognizes_definition_hints(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.lean-export"
            for tag in ("DEF", "ABBREV", "REGULAR", "HINT_OPAQUE", "OPAQUE", "AX", "IND", "QUOT"):
                with self.subTest(tag=tag):
                    source.write_text(f"0 #NS 0 mock\n#{tag} fixture\n", encoding="utf-8")
                    self.assertEqual(frontier.next_export_entry(source, 1),
                                     {"line": 2, "raw": f"#{tag} fixture"})

    @unittest.skipUnless(Path("/usr/bin/time").is_file() and hasattr(os, "killpg"), "requires POSIX process groups")
    def test_cancellation_reaches_guard_below_time_and_its_detached_child(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ready = root / "ready.json"
            guard = root / "fake_guard.py"
            guard.write_text("""import json
import os
from pathlib import Path
import signal
import subprocess
import sys

worker = subprocess.Popen(
    [sys.executable, '-c', 'import time\\nwhile True: time.sleep(0.05)'],
    start_new_session=True,
)

def stop(signum, frame):
    worker.terminate()
    worker.wait(timeout=3)
    Path(sys.argv[1]).with_name('stopped').touch()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, stop)
Path(sys.argv[1]).write_text(json.dumps({'guard': os.getpid(), 'worker': worker.pid}))
while True:
    signal.pause()
""", encoding="utf-8")
            process = subprocess.Popen(
                ["/usr/bin/time", "-v", sys.executable, str(guard), str(ready)],
                start_new_session=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            pids = {}
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and not ready.exists():
                    self.assertIsNone(process.poll())
                    time.sleep(0.02)
                self.assertTrue(ready.exists(), "fake process tree did not start")
                pids = json.loads(ready.read_text())
                frontier.stop_process(process)
                self.assertTrue((root / "stopped").exists(), "guard did not complete cleanup")
                with self.assertRaises(ProcessLookupError):
                    os.kill(pids["worker"], 0)
            finally:
                # Even a failing regression must leave no artificial workers.
                for pid in pids.values():
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.communicate(timeout=5)

    def test_jobs_are_rejected_during_argument_parsing(self) -> None:
        with patch("sys.argv", ["frontier", "input", "--jobs", "2"]):
            with contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    frontier.parse_args()
        self.assertEqual(raised.exception.code, 2)

    def test_signal_status_is_not_automatically_oom(self) -> None:
        self.assertEqual(frontier.exit_status(-9), 137)
        self.assertEqual(frontier.exit_status(137), 137)
        self.assertEqual(frontier.classify(
            137, saw_timeout=False, saw_import_error=False, saw_anomaly=False
        ), "checker-failure")

    def test_zero_status_does_not_hide_errors_or_skips(self) -> None:
        for flags, result in (
            ({"saw_import_error": True}, "import-error"),
            ({"saw_anomaly": True}, "rocq-anomaly"),
            ({"saw_skipped": True}, "incomplete-import"),
        ):
            with self.subTest(result=result):
                defaults = dict(saw_timeout=False, saw_import_error=False, saw_anomaly=False)
                self.assertEqual(frontier.classify(0, **(defaults | flags)), result)
        self.assertTrue(frontier.SKIPPED_RE.match("Skipped 2"))
        self.assertFalse(frontier.SKIPPED_RE.match("Skipped 0"))

    def test_guard_gets_cleanup_time_on_cancellation(self) -> None:
        process = Mock()
        process.pid = 12345
        process.communicate.side_effect = KeyboardInterrupt
        with patch.object(frontier.subprocess, "Popen", return_value=process) as popen, \
             patch.object(frontier.os, "killpg", side_effect=[None, None, ProcessLookupError]) as killpg, \
             patch.object(frontier.time, "sleep"):
            with self.assertRaises(KeyboardInterrupt):
                frontier.run_guarded(Path("guard"), ["fake"])
        self.assertTrue(popen.call_args.kwargs["start_new_session"])
        self.assertEqual(killpg.call_args_list[0].args, (process.pid, signal.SIGTERM))
        self.assertEqual(killpg.call_count, 3)
        process.wait.assert_called_once_with()
        process.terminate.assert_not_called()
        process.kill.assert_not_called()

    def test_guard_status_survives_preflight_failure(self) -> None:
        with patch.object(frontier.subprocess, "Popen", return_value=FakeProcess(status=75)):
            with self.assertRaises(subprocess.CalledProcessError) as raised:
                frontier.run_guarded(Path("guard"), ["fake"])
        self.assertEqual(raised.exception.returncode, 75)

    def test_configured_guard_grace_precedes_group_kill(self) -> None:
        process = Mock(pid=12345)
        with patch.dict(os.environ, {"ROCQ_MEMORY_TERM_GRACE_SECONDS": "60"}):
            self.assertEqual(frontier.guard_shutdown_timeout(), 95)
            with patch.object(frontier.os, "killpg") as killpg, \
                 patch.object(frontier.time, "monotonic", side_effect=[0, 90, 96]), \
                 patch.object(frontier.time, "sleep") as sleep:
                frontier.stop_process(process)
        self.assertEqual([call.args[1] for call in killpg.call_args_list],
                         [signal.SIGTERM, 0, 0, signal.SIGKILL])
        sleep.assert_called_once_with(0.05)
        process.wait.assert_called_once_with()

    def test_frontier_guards_build_and_version_without_double_wrapping_run(self) -> None:
        for no_build in (False, True):
            for status, output, expected_result in (
                (0, "line 1: mock\n", "success"),
                (0, "line 1: Anomaly\n", "success"),
                (0, "line 1: Error at line 42 Timed out after\n", "success"),
                (137, "", "checker-failure"),
                (0, "Skipped 2\n", "incomplete-import"),
                (0, "Error at line 1 (for mock): rejected\n", "import-error"),
                (0, 'Anomaly "Uncaught exception"\n', "rocq-anomaly"),
            ):
                with self.subTest(no_build=no_build, result=expected_result), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    source = root / "input"
                    source.write_text("#fixture\n", encoding="utf-8")
                    importer = root / "importer"
                    (importer / ".git").mkdir(parents=True)
                    args = argparse.Namespace(
                        input=source, importer_root=importer, opam_switch="mock",
                        expected_rocq="9.3", from_line=None, until_line=None,
                        progress_timeout=10, jobs=1, no_build=no_build,
                        state=root / "state.json", log_dir=root / "logs",
                    )
                    commands = []
                    run_environments = []

                    def popen(command, **kwargs):
                        self.assertTrue(kwargs["start_new_session"])
                        commands.append(command)
                        if command[-1] == "--version":
                            return FakeProcess("Rocq 9.3 mock\n")
                        if command[0] == "/usr/bin/time":
                            run_environments.append(kwargs["env"])
                            return FakeProcess(output, status)
                        return FakeProcess()

                    with patch.object(frontier, "parse_args", return_value=args), \
                         patch.object(frontier, "run_text", return_value="mock-commit"), \
                         patch.object(frontier.subprocess, "Popen", side_effect=popen), \
                         patch.dict(os.environ, {
                             "ROCQLKA_LEAN_ERROR_MODE": "Skip",
                             "ROCQLKA_LEAN_FROM": "100",
                             "ROCQLKA_LEAN_UNTIL": "200",
                         }), \
                         contextlib.redirect_stdout(io.StringIO()):
                        self.assertEqual(frontier.main(), status or int(expected_result != "success"))

                    self.assertEqual(len(commands), 2 if no_build else 3)
                    for command in commands[:-1]:
                        self.assertEqual(Path(command[0]).name, "run-memory-guarded.sh")
                    if not no_build:
                        self.assertIn("make", commands[0])
                        self.assertIn("-j1", commands[0])
                    self.assertEqual(commands[-1][:2], ["/usr/bin/time", "-v"])
                    self.assertEqual(Path(commands[-1][2]).name, "run.sh")
                    self.assertEqual(run_environments[0]["ROCQLKA_LEAN_ERROR_MODE"], "Fail")
                    self.assertNotIn("ROCQLKA_LEAN_FROM", run_environments[0])
                    self.assertNotIn("ROCQLKA_LEAN_UNTIL", run_environments[0])
                    record = json.loads(args.state.read_text())["latest"]
                    self.assertEqual(record["returncode"], status)
                    self.assertEqual(record["result"], expected_result)


if __name__ == "__main__":
    unittest.main()
