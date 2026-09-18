"""Manual Mathlib orchestration tests; no real compiler, exporter, guard or model."""

import argparse
from contextlib import ExitStack, redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_mathlib_from_start as runner


class MathlibRunnerTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.root = Path(self.stack.enter_context(tempfile.TemporaryDirectory()))
        self.stack.enter_context(redirect_stdout(io.StringIO()))
        self.replace(runner, "ROOT", self.root)
        self.replace(runner, "RUNS", self.root / "mathlib-runs")
        self.replace(runner, "BUNDLE", self.root / "exports/full")
        self.replace(runner, "EXPORT", runner.BUNDLE / "Mathlib.lean-export")
        self.replace(runner, "SCRIPT", self.root / "mathlib.py")
        for name in ("ROCQ", "KERNEL", "IMPORTER", "STDLIB", "GUARD", "SCRIPT"):
            self.replace(runner.checking, name, self.root / name.lower())
        for name in ("NDJSON", "STATS", "SPEC", "CONVERTER"):
            self.replace(runner, name, self.root / name.lower())
        for path in [*runner.checker_inputs(), runner.checking.STDLIB / "Numbers/BinNums.vo",
                     *runner.reference_inputs()]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        self.metadata = {"lean": {"version": "4.29.0", "githash": runner.LEAN_REVISION},
                         "exporter": {"version": "3.1.0"}, "format": {"version": "3.1.0"}}
        runner.NDJSON.write_text(json.dumps({"meta": self.metadata}) + "\n")
        self.stats = {"size": runner.NDJSON.stat().st_size, "lines": 1,
                      "lean_version": "4.29.0", "lean_githash": runner.LEAN_REVISION,
                      "lean4export_version": "3.1.0", "name": "mathlib",
                      "source_url": "https://github.com/leanprover-community/mathlib4/tree/" + runner.REVISION}
        runner.save_json(runner.STATS, self.stats)
        runner.SPEC.write_text("url: https://github.com/leanprover-community/mathlib4\n"
                               "ref: v4.29.0\nrev: " + runner.REVISION + "\nmodule: Mathlib\n")
        self.args = argparse.Namespace(directory=self.root / "run", memory_mib=16384,
                                       line_timeout=600, dry_run=False)

    def replace(self, obj, name, value):
        self.stack.enter_context(patch.object(obj, name, value))

    def export_mocks(self):
        self.stack.enter_context(patch.object(runner, "require_guard"))
        self.stack.enter_context(patch.object(runner, "disk_gate"))

    def test_dry_run_does_not_hash_write_or_launch(self):
        self.args.dry_run = True
        with patch.object(runner.checking, "fingerprint") as digest, \
                patch.object(runner.checking, "wait_for_guard") as guard, \
                redirect_stdout(io.StringIO()) as output:
            self.assertEqual(runner.launch(self.args), 0)
            digest.assert_not_called()
            guard.assert_not_called()
        plan = json.loads(output.getvalue())
        self.assertEqual(plan["toolchain"], "leanprover/lean4:v4.29.0")
        self.assertEqual(plan["ndjson"], str(runner.NDJSON))
        self.assertIn("convert existing reference NDJSON", plan["export_action"])
        self.assertFalse(runner.RUNS.exists())
        self.assertFalse(self.args.directory.exists())

    def test_missing_input_is_refused_before_creating_run(self):
        runner.NDJSON.unlink()
        with self.assertRaisesRegex(ValueError, "Required input is missing"):
            runner.launch(self.args)
        self.assertFalse(runner.RUNS.exists())

    def test_hidden_export_and_check_worker_requires_guard(self):
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(runner, "convert_reference") as convert, \
                patch.object(runner.checking, "worker") as checking:
            for action in (runner.prepare_export, lambda: runner.worker(self.args.directory)):
                with self.assertRaisesRegex(ValueError, "requires the memory guard"):
                    action()
            convert.assert_not_called()
            checking.assert_not_called()

    def test_scope_marker_alone_is_not_sufficient(self):
        with patch.dict(os.environ, {"_ROCQ_MEMORY_GUARD_SCOPED": "1"}), \
                patch.object(Path, "read_text", return_value="0::/unrelated.scope\n"):
            with self.assertRaisesRegex(ValueError, "requires the memory guard"):
                runner.require_guard()

    def test_reference_conversion_is_published_only_on_success(self):
        self.export_mocks()
        original = runner.NDJSON.read_bytes()

        def convert(output):
            self.assertFalse(runner.BUNDLE.exists())
            output.write_text("one\ntwo\n")

        with patch.object(runner, "convert_reference", side_effect=convert) as conversion:
            source, fingerprint = runner.prepare_export()
            conversion.assert_called_once()
        self.assertEqual(fingerprint["lines"], 2)
        record = json.loads((runner.BUNDLE / "provenance.json").read_text())
        self.assertEqual(record["source"], source)
        self.assertEqual(record["module"], "Mathlib")
        self.assertEqual(record["export_fingerprint"], fingerprint)
        self.assertEqual(record["ndjson"], str(runner.NDJSON))
        self.assertEqual(set(record["inputs"]), set(map(str, runner.reference_inputs())))
        self.assertTrue(record["streaming"])
        self.assertEqual(runner.NDJSON.read_bytes(), original)

    def test_conversion_launches_only_streaming_converter_on_existing_ndjson(self):
        output = self.root / "converted"
        with patch.object(runner, "disk_gate"), patch.object(runner.subprocess, "Popen") as popen:
            popen.return_value.wait.return_value = 0
            popen.return_value.poll.return_value = 0
            runner.convert_reference(output)
        popen.assert_called_once()
        args, kwargs = popen.call_args
        self.assertEqual(args[0], [sys.executable, str(runner.CONVERTER), str(runner.NDJSON), str(output)])
        self.assertEqual(kwargs["env"]["ROCQLKA_NDJSON_STREAM"], "1")

    def test_converter_failure_and_disk_reserve_stop_preparation(self):
        with patch.object(runner, "disk_gate"), patch.object(runner.subprocess, "Popen") as popen:
            popen.return_value.wait.return_value = 2
            popen.return_value.poll.return_value = 2
            with self.assertRaises(subprocess.CalledProcessError):
                runner.convert_reference(self.root / "converted")
        with patch.object(runner, "disk_gate", side_effect=ValueError("disk reserve")), \
                patch.object(runner.subprocess, "Popen") as popen:
            popen.return_value.poll.return_value = None
            with self.assertRaisesRegex(ValueError, "disk reserve"):
                runner.convert_reference(self.root / "converted")
            popen.return_value.terminate.assert_called_once()
            popen.return_value.wait.assert_called_once_with(timeout=5)

    def test_wrong_version_revision_and_truncated_reference_are_refused(self):
        for field, value, message in (("lean_version", "4.27.0-rc1", "metadata"),
                                      ("source_url", "wrong revision", "metadata"),
                                      ("size", self.stats["size"] + 1, "size")):
            with self.subTest(field=field):
                runner.save_json(runner.STATS, dict(self.stats, **{field: value}))
                with self.assertRaisesRegex(ValueError, message):
                    runner.inspect_reference()
        runner.save_json(runner.STATS, self.stats)
        runner.SPEC.write_text(runner.SPEC.read_text().replace("v4.29.0", "v4.27.0-rc1"))
        with self.assertRaisesRegex(ValueError, "specification"):
            runner.inspect_reference()

    def test_wrong_ndjson_header_is_refused(self):
        self.metadata["lean"]["githash"] = "wrong kernel"
        runner.NDJSON.write_text(json.dumps({"meta": self.metadata}) + "\n")
        with self.assertRaisesRegex(ValueError, "metadata"):
            runner.inspect_reference()

    def test_incomplete_ndjson_and_changed_conversion_input_are_not_published(self):
        self.export_mocks()
        runner.save_json(runner.STATS, dict(self.stats, lines=2))
        with patch.object(runner, "convert_reference") as conversion:
            with self.assertRaisesRegex(ValueError, "line count"):
                runner.prepare_export()
            conversion.assert_not_called()
        runner.save_json(runner.STATS, self.stats)

        def changed(output):
            output.write_text("one\n")
            runner.CONVERTER.write_text("changed during conversion\n")

        with patch.object(runner, "convert_reference", side_effect=changed):
            with self.assertRaisesRegex(ValueError, "Input changed"):
                runner.prepare_export()
        self.assertFalse(runner.BUNDLE.exists())

    def test_failed_or_empty_export_is_never_published(self):
        self.export_mocks()
        with patch.object(runner, "convert_reference", side_effect=ValueError("export failed")):
            with self.assertRaisesRegex(ValueError, "export failed"):
                runner.prepare_export()
        self.assertFalse(runner.BUNDLE.exists())
        with patch.object(runner, "convert_reference", side_effect=lambda out: out.touch()):
            with self.assertRaisesRegex(ValueError, "export is empty"):
                runner.prepare_export()
        self.assertFalse(runner.BUNDLE.exists())
        self.assertEqual(len(list(runner.BUNDLE.parent.glob(".full.stage-*"))), 2)

    def test_cached_export_is_verified_and_never_silently_replaced(self):
        self.export_mocks()
        with patch.object(runner, "convert_reference", side_effect=lambda out: out.write_text("x\n")):
            runner.prepare_export()
        with patch.object(runner, "convert_reference") as conversion:
            runner.prepare_export()
            conversion.assert_not_called()
            runner.EXPORT.write_text("tampered\n")
            with self.assertRaisesRegex(ValueError, "export changed"):
                runner.prepare_export()
            runner.EXPORT.write_text("x\n")
            runner.CONVERTER.write_text("new converter\n")
            with self.assertRaisesRegex(ValueError, "inputs changed"):
                runner.prepare_export()
            conversion.assert_not_called()

    def test_worker_builds_fresh_foundation_and_strict_full_source(self):
        directory = self.args.directory
        directory.mkdir()
        runner.save_json(directory / "settings.json", {"created": "now", "memory_mib": 16384,
                                                      "line_timeout": 600})
        with patch.object(runner, "require_guard"), \
                patch.object(runner, "prepare_export", return_value=({}, {"lines": 22, "sha256": "export"})), \
                patch.object(runner, "disk_gate"), \
                patch.object(runner.checking, "git_state", return_value={"head": "test"}), \
                patch.object(runner.checking, "worker", return_value=0) as checking:
            self.assertEqual(runner.worker(directory), 0)
            checking.assert_called_once_with(directory)
        source = (directory / "Full.v").read_text()
        self.assertIn('Set Lean Error Mode "Fail".', source)
        self.assertIn('" 1 23.', source)
        self.assertNotIn("Prefix", source)
        self.assertTrue((directory / "foundation/Lean.v").exists())
        self.assertFalse((directory / "foundation/Lean.vo").exists())

    def test_one_guard_separate_latest_and_no_success_on_missing_artifact(self):
        cslib_runs = runner.checking.RUNS
        for status, artifact, success in ((0, True, True), (0, False, False), (75, False, False)):
            with self.subTest(status=status, artifact=artifact):
                self.args.directory = self.root / ("run-%s-%s" % (status, artifact))

                def guarded(command, **kwargs):
                    self.assertEqual(command[:2], ["bash", str(runner.checking.GUARD)])
                    self.assertIn("--worker", command)
                    self.assertEqual(kwargs["env"]["ROCQ_MEMORY_MAX_KIB"], str(16 * 1024**2))
                    self.assertEqual(kwargs["env"]["ROCQ_ALLOW_EXTERNAL_ROCQ"], "0")
                    if artifact:
                        (self.args.directory / "Full.vo").write_text("compiled")
                    return status

                with patch.object(runner.checking, "wait_for_guard", side_effect=guarded) as guard:
                    code = runner.launch(self.args)
                    guard.assert_called_once()
                result = json.loads((self.args.directory / "result.json").read_text())
                self.assertEqual(result["success"], success)
                self.assertEqual(code == 0, success)
                self.assertEqual((runner.RUNS / "latest").resolve(), self.args.directory)
        self.assertEqual(runner.checking.RUNS, cslib_runs)

    def test_second_manual_runner_does_not_change_latest(self):
        runner.RUNS.mkdir()
        with (runner.RUNS / "runner.lock").open("a") as lock:
            runner.fcntl.flock(lock, runner.fcntl.LOCK_EX | runner.fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, "already owns the runner"):
                runner.launch(self.args)
        self.assertFalse((runner.RUNS / "latest").exists())
        self.assertFalse(self.args.directory.exists())

    def test_existing_directory_and_nested_guard_are_refused(self):
        self.args.directory.mkdir()
        with self.assertRaisesRegex(ValueError, "must be new"):
            runner.launch(self.args)
        with patch.dict(os.environ, {"_ROCQ_MEMORY_GUARD_SCOPED": "1"}):
            with self.assertRaisesRegex(ValueError, "Do not nest"):
                runner.launch(self.args)


if __name__ == "__main__":
    unittest.main()
