"""Export safety tests using tiny subprocesses, never Lean or Rocq."""

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_mathlib as prep


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.export = self.root / "Mathlib.lean-export"
        self.converter = self.root / "converter.py"
        self.converter.write_text("import pathlib,sys\npathlib.Path(sys.argv[2]).write_bytes(sys.stdin.buffer.read())\n")
        for name, value in (("SOURCE", self.root), ("CONVERTER", self.converter)):
            p = patch.object(prep, name, value)
            p.start()
            self.addCleanup(p.stop)

    def test_pipeline_streams_instead_of_storing_raw_ndjson(self):
        prep.pipeline([sys.executable, "-c", "print('tiny NDJSON')"], self.export, dict(os.environ), reserve=0)
        self.assertEqual(self.export.read_text(), "tiny NDJSON\n")
        self.assertEqual(list(self.root.glob("*.ndjson")), [])

    def test_successful_converter_does_not_hide_failed_exporter(self):
        with self.assertRaisesRegex(prep.chunks.Refused, r"\(7/0\)"):
            prep.pipeline([sys.executable, "-c", "import sys; print('partial'); sys.exit(7)"],
                          self.export, dict(os.environ), reserve=0)

    def test_converter_failure_does_not_promote_partial_export(self):
        self.converter.write_text("import sys; sys.exit(6)\n")
        with self.assertRaises(prep.chunks.Refused):
            prep.pipeline([sys.executable, "-c", "print('partial')"], self.export, dict(os.environ), reserve=0)

    def test_disk_refusal_stops_pipeline(self):
        with patch.object(prep, "disk_gate", side_effect=prep.chunks.Refused("low disk")):
            with self.assertRaisesRegex(prep.chunks.Refused, "low disk"):
                prep.pipeline([sys.executable, "-c", "import time; time.sleep(30)"], self.export, dict(os.environ))

    def test_preparation_requires_explicit_toolchain(self):
        with self.assertRaisesRegex(prep.chunks.Refused, "toolchain"):
            prep.prepare()

    def bundle(self):
        self.export.write_text("checked export")
        self.tool = self.root / "exporter"
        self.tool.write_text("exporter binary")
        source = {"mathlib_revision": prep.REVISION, "toolchain": prep.TOOLCHAIN}
        record = {"source": source, "module": "Mathlib", "declarations": [],
                  "inputs": {str(self.tool): prep.chunks.sha(self.tool)}, "export_sha256": prep.chunks.sha(self.export)}
        (self.root / "provenance.json").write_text(json.dumps(record))
        return source

    def test_bundle_hashes_are_verified_before_reuse(self):
        source = self.bundle()
        prep.verify_bundle(self.root, source, "Mathlib", [])
        self.export.write_text("changed")
        with self.assertRaises(prep.chunks.Refused):
            prep.verify_bundle(self.root, source, "Mathlib", [])

    def test_wrong_revision_or_declaration_filter_cannot_reuse_full_export(self):
        source = self.bundle()
        for wrong_source, declarations in ((source, ["only.one.theorem"]), ({"toolchain": "v4.29"}, [])):
            with self.assertRaises(prep.chunks.Refused):
                prep.verify_bundle(self.root, wrong_source, "Mathlib", declarations)

    def test_changed_exporter_invalidates_cached_bundle(self):
        source = self.bundle()
        self.tool.write_text("new binary")
        with self.assertRaises(prep.chunks.Refused):
            prep.verify_bundle(self.root, source, "Mathlib", [])

    def test_disk_admission_is_explicit(self):
        with patch.object(prep.shutil, "disk_usage", return_value=Mock(free=3 * prep.GIB)):
            with self.assertRaises(prep.chunks.Refused):
                prep.disk_gate(self.root, 12 * prep.GIB)

    def test_full_preparation_uses_full_module_and_unseeded_2m_plan(self):
        source = {"packages": [], "toolchain": prep.TOOLCHAIN, "mathlib_revision": prep.REVISION}
        profile = self.root / "toolchain.json"
        profile.write_text("{}")
        plan_path = self.root / "checkpoints/full/plan.json"
        with patch.object(prep, "OUTPUT", self.root / "bundles"), \
                patch.object(prep, "PLAN", plan_path), \
                patch.object(prep, "inspect_source", return_value=source), \
                patch.object(prep, "input_hashes", return_value={str(profile): prep.chunks.sha(profile)}), \
                patch.object(prep, "disk_gate"), \
                patch.object(prep, "pipeline", side_effect=lambda cmd, out, env: out.write_bytes(b"record\n" * 9)) as pipeline:
            prep.prepare(toolchain=profile)
        command = pipeline.call_args.args[0]
        self.assertEqual(command, [str(prep.EXPORTER), "Mathlib"])
        plan = json.loads(plan_path.read_text())
        self.assertEqual(plan["interval"], 2_000_000)
        self.assertEqual(plan["chunks"][0]["start"], 1)
        self.assertIsNone(plan["seed"])
        self.assertEqual(plan["toolchain"]["sha256"], prep.chunks.sha(profile))

    def test_failed_preparation_does_not_publish_a_bundle_or_plan(self):
        profile = self.root / "toolchain.json"
        profile.write_text("{}")
        with patch.object(prep, "OUTPUT", self.root / "bundles"), \
                patch.object(prep, "PLAN", self.root / "plan.json"), \
                patch.object(prep, "inspect_source", return_value={"packages": []}), \
                patch.object(prep, "input_hashes", return_value={}), patch.object(prep, "disk_gate"), \
                patch.object(prep, "pipeline", side_effect=prep.chunks.Refused("export failed")):
            with self.assertRaises(prep.chunks.Refused):
                prep.prepare(toolchain=profile)
        self.assertFalse((self.root / "bundles/full").exists())
        self.assertFalse((self.root / "plan.json").exists())


if __name__ == "__main__":
    unittest.main()
