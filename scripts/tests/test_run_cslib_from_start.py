"""Manual full-pass runner tests; no real compiler, guard or model call."""

import argparse
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_cslib_from_start as runner


class ManualRunnerTests(unittest.TestCase):
    def test_streaming_line_count_includes_unterminated_final_line(self):
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "input"
            for content, count in ((b"", 0), (b"x", 1), (b"x\n", 1), (b"x\ny", 2)):
                source.write_bytes(content)
                self.assertEqual(runner.fingerprint(source)["lines"], count)

    def test_full_source_has_explicit_complete_range_and_strict_settings(self):
        source = runner.full_source(Path('/a"b/input'), 22, 60)
        self.assertIn('Lean Import "/a""b/input" 1 23.', source)
        for setting in ('Set Lean Error Mode "Fail".', "Unset Lean Skip Missing Quotient.",
                        "Unset Lean Just Parsing.", "Unset Lean Lazy Instantiation."):
            self.assertIn(setting, source)
        self.assertNotIn("Prefix", source)
        self.assertEqual(source.count("Require"), 1)

    def test_environment_cannot_weaken_guards_or_enable_diagnostics(self):
        with patch.dict(os.environ, {"LEAN_IMPORT_ANYTHING": "1", "ROCQ_DIAGNOSTIC_FAST": "1",
                                     "ROCQ_ALLOW_EXTERNAL_ROCQ": "1", "COQPATH": "/old/checkpoints"}):
            env = runner.environment(16384)
        self.assertNotIn("LEAN_IMPORT_ANYTHING", env)
        self.assertNotIn("ROCQ_DIAGNOSTIC_FAST", env)
        self.assertNotIn("COQPATH", env)
        self.assertEqual(env["ROCQ_MEMORY_MAX_KIB"], str(16 * 1024**2))
        self.assertEqual(env["ROCQ_MAX_RSS_KIB"], str(15 * 1024**2))
        self.assertEqual(env["ROCQ_MIN_AVAILABLE_KIB"], str(3 * 1024**2))
        self.assertEqual(env["ROCQ_MEMORY_SWAP_MAX_KIB"], "0")
        self.assertEqual(env["ROCQ_ALLOW_EXTERNAL_ROCQ"], "0")
        self.assertEqual(env["OCAMLRUNPARAM"], "s=4M,o=80,i=15,a=2,v=0,b")

    def test_dry_run_has_no_hash_write_or_process(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            export = root / "export"
            export.write_text("input\n")
            args = argparse.Namespace(export=export, directory=root / "run", memory_mib=1024,
                                      line_timeout=60, dry_run=True)
            with patch.object(Path, "is_file", return_value=True), \
                    patch.object(runner, "fingerprint") as digest, \
                    patch.object(runner, "git_state") as git, \
                    patch.object(runner, "wait_for_guard") as run, redirect_stdout(io.StringIO()):
                self.assertEqual(runner.launch(args), 0)
                digest.assert_not_called()
                git.assert_not_called()
                run.assert_not_called()
            self.assertFalse(args.directory.exists())

    def test_existing_directory_is_never_reused(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(Path, "is_file", return_value=True):
            args = argparse.Namespace(export=Path(temp), directory=Path(temp), dry_run=True)
            with self.assertRaisesRegex(ValueError, "must be new"):
                runner.launch(args)

    def test_worker_requires_guard(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(runner.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "memory guard"):
                runner.worker(Path("unused"))
            run.assert_not_called()

    def test_launch_records_inputs_and_creates_only_fresh_foundation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            export = root / "fixture.export"
            export.write_text("a\nb\n")
            (root / "importer/src").mkdir(parents=True)
            (root / "importer/src/Lean.v").write_text("fresh source\n")
            args = argparse.Namespace(export=export, directory=root / "run", memory_mib=3072,
                                      line_timeout=30, dry_run=False)

            def guarded_fake(command, **kwargs):
                self.assertEqual(command[:2], ["bash", str(runner.GUARD)])
                self.assertIn("--worker", command)
                self.assertFalse((args.directory / "foundation/Lean.vo").exists())
                self.assertFalse((args.directory / "result.json").exists())
                self.assertEqual((args.directory / "foundation/Lean.v").read_text(), "fresh source\n")
                (args.directory / "Full.vo").write_bytes(b"compiled")
                return 0

            with patch.object(runner, "RUNS", root / "runs"), \
                    patch.object(runner, "IMPORTER", root / "importer"), \
                    patch.object(Path, "is_file", return_value=True), \
                    patch.object(runner, "fingerprint", return_value={"sha256": "digest", "lines": 2}), \
                    patch.object(runner, "git_state", return_value={"head": "revision", "status": "dirty"}), \
                    patch.object(runner, "wait_for_guard", side_effect=guarded_fake) as run, \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(runner.launch(args), 0)
                self.assertEqual(run.call_count, 1)
            manifest = json.loads((args.directory / "manifest.json").read_text())
            self.assertEqual(manifest["mode"], "manual-from-line-1")
            self.assertEqual(manifest["export_fingerprint"]["lines"], 2)
            self.assertEqual(manifest["importer"]["status"], "dirty")
            self.assertTrue(json.loads((args.directory / "result.json").read_text())["success"])
            self.assertEqual((root / "runs/latest").resolve(), args.directory)

    def test_cancellation_forwards_once_and_waits_for_cleanup(self):
        for signum in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=signum):
                handlers, events = {}, []
                previous = {sig: object() for sig in (signal.SIGINT, signal.SIGTERM)}
                process = Mock()
                process.send_signal.side_effect = lambda sig: events.append(("forward", sig))

                def wait():
                    handlers[signum](signum, None)
                    handlers[signum](signum, None)
                    events.append("cleanup finished")
                    return 0  # Cancellation must not become success.

                process.wait.side_effect = wait
                with patch.object(runner.signal, "getsignal", side_effect=previous.__getitem__), \
                        patch.object(runner.signal, "signal", side_effect=handlers.__setitem__), \
                        patch.object(runner.subprocess, "Popen", return_value=process) as launch:
                    self.assertEqual(runner.wait_for_guard(["guard"]), 128 + signum)
                self.assertEqual(events, [("forward", signum), "cleanup finished"])
                self.assertEqual(handlers, previous)
                launch.assert_called_once_with(["guard"], start_new_session=True)
                process.wait.assert_called_once_with()

    def test_guard_signal_exit_is_normalized_and_handlers_restored(self):
        handlers = {}
        previous = {sig: object() for sig in (signal.SIGINT, signal.SIGTERM)}
        process = Mock()
        process.wait.return_value = -signal.SIGTERM
        with patch.object(runner.signal, "getsignal", side_effect=previous.__getitem__), \
                patch.object(runner.signal, "signal", side_effect=handlers.__setitem__), \
                patch.object(runner.subprocess, "Popen", return_value=process):
            self.assertEqual(runner.wait_for_guard(["guard"]), 143)
        self.assertEqual(handlers, previous)
        process.send_signal.assert_not_called()

    def test_worker_compiles_fresh_foundation_then_full_in_sequence(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "foundation").mkdir()
            calls = []

            def compile_fake(command, **kwargs):
                calls.append(command[-1])
                (kwargs["cwd"] / command[-1]).with_suffix(".vo").write_bytes(b"compiled")
                return subprocess.CompletedProcess(command, 0)

            with patch.dict(os.environ, {"_ROCQ_MEMORY_GUARD_SCOPED": "1"}), \
                    patch.object(Path, "read_text", return_value="0::/rocq-lean-import-heavy.scope\n"), \
                    patch.object(runner.subprocess, "run", side_effect=compile_fake):
                self.assertEqual(runner.worker(directory), 0)
            self.assertEqual(calls, ["Lean.v", "Full.v"])

    def test_failed_foundation_does_not_launch_full_pass(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "foundation").mkdir()
            with patch.dict(os.environ, {"_ROCQ_MEMORY_GUARD_SCOPED": "1"}), \
                    patch.object(Path, "read_text", return_value="0::/rocq-lean-import-heavy.scope\n"), \
                    patch.object(runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)) as run:
                self.assertEqual(runner.worker(directory), 1)
                self.assertEqual(run.call_count, 1)
                self.assertFalse((directory / "Full.run.log").exists())


if __name__ == "__main__":
    unittest.main()
