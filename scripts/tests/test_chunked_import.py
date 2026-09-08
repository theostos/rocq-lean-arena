"""Chunk scheduling and recovery tests; no Rocq process or model is launched."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_chunked_import as chunked


class ChunkedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.export = self.root / "test.lean-export"
        self.export.write_bytes(b"0 #NS 0 example\n" * 9)
        self.out = self.root / "checkpoints"
        self.plan = chunked.prepare(self.export, self.out, "Example", interval=3)
        self.plan_path = self.out / "plan.json"
        self.worker = self.root / "worker"
        self.worker.write_text("worker-v1")
        self.pin = self.root / "pin.sh"
        self.pin.write_text("pinned-worker-v1")
        self.calls = []
        self.fail = None
        disk = patch.object(chunked.shutil, "disk_usage", return_value=Mock(free=20 * 1024**3))
        disk.start()
        self.addCleanup(disk.stop)
        for name, value in (("OLD_RUN", self.root), ("WORKER", self.worker), ("PIN", self.pin)):
            p = patch.object(chunked, name, value)
            p.start()
            self.addCleanup(p.stop)

    def fake_compile(self, directory, module, attempt, sealed, inputs, memory_mib):
        self.calls.append(module)
        if module == self.fail:
            raise chunked.CompileFailed(1)
        (directory / (module + ".vo")).write_text("checked " + module)
        if sealed:
            seal = directory / (module + ".seal")
            seal.mkdir()
            source = directory / (module + ".v")
            (seal / "inputs.sha256").write_text(inputs.read_text() + chunked.sha(source) + "  " + str(source) + "\n")
            artifact = directory / (module + ".vo")
            (seal / "artifact.sha256").write_text(chunked.sha(artifact) + "  " + str(artifact) + "\n")

    def fake_inputs(self, plan_path, plan, predecessors):
        paths = [plan_path, self.export, self.worker, self.pin]
        paths += [self.out / (c["module"] + ".vo") for c in predecessors]
        return {str(p): chunked.sha(p) for p in paths}

    def run_plan(self, name, pause_file=None):
        with patch.object(chunked, "preflight"), \
                patch.object(chunked, "current_inputs", side_effect=self.fake_inputs), \
                patch.object(chunked, "compile_module", side_effect=self.fake_compile):
            chunked.run(self.plan_path, self.root / name, pause_file)

    def test_contiguous_end_exclusive_intervals(self):
        self.assertEqual([(c["start"], c["end"]) for c in self.plan["chunks"]], [(1, 4), (4, 7), (7, 10)])
        self.assertEqual(self.plan["lines"], 9)
        self.assertEqual(self.plan["export_sha256"], chunked.sha(self.export))

    def test_mutual_block_is_not_split(self):
        rows = [b"node\n", b"#IND first\n", b"#IND second\n", b"node\n", b"node\n"]
        ends, total, _ = chunked.boundaries(rows, 1, 2)
        self.assertEqual(ends, [5, 6])
        self.assertEqual(total, 5)

    def test_mutual_block_at_eof_is_flushed_together(self):
        ends, _, _ = chunked.boundaries([b"node\n", b"#IND A\n", b"#IND B\n"], 1, 2)
        self.assertEqual(ends, [4])

    def test_seed_does_not_change_line_numbering(self):
        ends, _, _ = chunked.boundaries([b"x\n"] * 17, 8, 4)
        self.assertEqual(ends, [12, 16, 18])

    def test_resume_requires_a_seed(self):
        with self.assertRaises(chunked.Refused):
            chunked.prepare(self.export, self.root / "bad", "Bad", start=4)

    def test_drivers_force_fail_mode_and_reload_parser(self):
        first = (self.out / "ExampleTo3.v").read_text()
        second = (self.out / "ExampleTo6.v").read_text()
        reload = (self.out / "ExampleTo3Reload.v").read_text()
        self.assertIn('Set Lean Error Mode "Fail".', first)
        self.assertIn('Unset Lean Just Parsing.', first)
        self.assertNotIn('Require Import Prefix15M', first)
        self.assertIn('Require Import ExampleTo3.', second)
        self.assertIn(' 4 7.', second)
        self.assertIn(' 4 4.', reload)

    def test_cannot_overwrite_a_different_source(self):
        (self.out / "ExampleTo3.v").write_text("Set Lean Just Parsing.")
        with self.assertRaises(chunked.Refused):
            chunked.load_plan(self.plan_path)

    def test_cannot_overwrite_plan(self):
        with self.assertRaises(chunked.Refused):
            chunked.prepare(self.export, self.out, "Example", interval=2)

    def test_gap_overlap_or_incomplete_plan_is_rejected(self):
        for key, value in (("start", 3), ("end", 8), ("parent", "Wrong")):
            original = json.loads(json.dumps(self.plan))
            original["chunks"][1][key] = value
            chunked.save_json(self.plan_path, original)
            with self.assertRaisesRegex(chunked.Refused, "gap, overlap or invalid module"):
                chunked.load_plan(self.plan_path)

    def test_failure_preserves_two_checkpoints_and_resumes_only_tail(self):
        self.fail = "ExampleTo9"
        with self.assertRaises(chunked.CompileFailed):
            self.run_plan("attempt1")
        self.assertEqual(json.loads((self.out / "progress.json").read_text())["next_line"], 7)
        self.assertFalse((self.out / "complete.json").exists())
        self.fail = None
        self.calls.clear()
        self.run_plan("attempt2")
        self.assertEqual(self.calls, ["ExampleTo6Reload", "ExampleTo9", "ExampleTo9Reload"])
        with patch.object(chunked, "preflight"):
            chunked.verify_complete(self.plan_path)

    def test_reload_failure_does_not_advance_progress(self):
        self.fail = "ExampleTo6Reload"
        with self.assertRaises(chunked.CompileFailed):
            self.run_plan("attempt1")
        self.assertEqual(json.loads((self.out / "progress.json").read_text())["next_line"], 4)
        self.fail = None
        self.calls.clear()
        self.run_plan("attempt2")
        self.assertEqual(self.calls[0], "ExampleTo6Reload")
        self.assertNotIn("ExampleTo6", self.calls)

    def test_completed_chain_only_needs_a_fresh_reload(self):
        self.run_plan("attempt1")
        self.calls.clear()
        self.run_plan("attempt2")
        self.assertEqual(self.calls, ["ExampleTo9Reload"])

    def test_corrupt_checkpoint_is_not_silently_recompiled(self):
        self.run_plan("attempt1")
        (self.out / "ExampleTo3.vo").write_text("corrupt")
        self.calls.clear()
        with self.assertRaises(chunked.Refused):
            self.run_plan("attempt2")
        self.assertEqual(self.calls, [])

    def test_orphan_checkpoint_refuses_overwrite(self):
        (self.out / "ExampleTo3.vo").write_text("unsealed")
        with self.assertRaises(chunked.Refused):
            self.run_plan("attempt1")

    def test_worker_migration_records_old_hash_without_rewriting_seal(self):
        self.run_plan("attempt1")
        seal = self.out / "ExampleTo3.seal/inputs.sha256"
        original = seal.read_bytes()
        self.worker.write_text("worker-v2")
        migrations = chunked.verify_saved(self.out, self.plan["chunks"][0])
        self.assertEqual(migrations[0]["path"], str(self.worker))
        self.assertEqual(seal.read_bytes(), original)
        self.run_plan("attempt2")
        self.assertEqual(seal.read_bytes(), original)

    def test_changed_export_is_not_an_allowed_migration(self):
        self.run_plan("attempt1")
        self.export.write_text("other export")
        with self.assertRaises(chunked.Refused):
            chunked.verify_saved(self.out, self.plan["chunks"][0])

    def test_stop_during_checkpoint_does_not_create_completion(self):
        self.fail = "ExampleTo3"
        with self.assertRaises(chunked.CompileFailed):
            self.run_plan("attempt1")
        self.assertFalse((self.out / "progress.json").exists())
        self.assertFalse((self.out / "complete.json").exists())

    def test_checkpoint_profiles_cannot_raise_the_memory_cap(self):
        with self.assertRaises(chunked.Refused):
            chunked.prepare(self.export, self.root / "bad", "Bad", memory_mib=32768)

    def test_disk_refusal_does_not_launch_or_delete_anything(self):
        with patch.object(chunked.shutil, "disk_usage", return_value=Mock(free=1024**3)):
            with self.assertRaises(chunked.Refused):
                self.run_plan("attempt1")
        self.assertEqual(self.calls, [])
        self.assertTrue(self.plan_path.is_file())

    def test_pause_before_first_chunk_launches_nothing(self):
        pause = self.root / "PAUSE"
        pause.touch()
        with self.assertRaises(chunked.CompileFailed) as raised:
            self.run_plan("attempt1", pause)
        self.assertEqual(raised.exception.code, 75)
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
