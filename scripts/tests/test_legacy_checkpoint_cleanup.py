"""The cleanup scope is explicit and the audit must still match before removal."""

import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import clean_legacy_checkpoints as cleanup


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.old = self.root / "old"
        self.old.mkdir()
        self.vo = self.old / "CslibOld.vo"
        self.vo.write_bytes(b"old compiled checkpoint")
        self.source = self.vo.with_suffix(".v")
        self.source.write_text("source retained")
        for name, value in (("ROOT", self.root), ("DIRECTORIES", (self.old,))):
            p = patch.object(cleanup, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.manifest = self.root / "audit.json"
        self.manifest.write_text(json.dumps({"format": "legacy-checkpoint-cleanup-v1", "files": cleanup.candidates()}))
        p = patch.object(cleanup, "in_use", return_value=[])
        p.start()
        self.addCleanup(p.stop)

    def test_removes_only_audited_binary_and_keeps_source(self):
        with patch.object(cleanup, "in_use", return_value=[]):
            cleanup.remove(self.manifest)
        self.assertFalse(self.vo.exists())
        self.assertEqual(self.source.read_text(), "source retained")
        self.assertEqual(json.loads(self.manifest.read_text())["removed"], [str(self.vo)])

    def test_modified_binary_refuses_removal(self):
        self.vo.write_bytes(b"new checkpoint")
        with self.assertRaises(ValueError):
            cleanup.remove(self.manifest)
        self.assertTrue(self.vo.exists())

    def test_modified_source_refuses_removal(self):
        self.source.write_text("new source")
        with self.assertRaises(ValueError):
            cleanup.remove(self.manifest)
        self.assertTrue(self.vo.exists())

    def test_active_use_refuses_removal(self):
        with patch.object(cleanup, "in_use", side_effect=ValueError("open file")):
            with self.assertRaises(ValueError):
                cleanup.remove(self.manifest)
        self.assertTrue(self.vo.exists())

    def test_external_path_in_audit_is_rejected(self):
        record = json.loads(self.manifest.read_text())
        record["files"][0]["path"] = str(self.root / "CslibOther.vo")
        self.manifest.write_text(json.dumps(record))
        with self.assertRaises(ValueError):
            cleanup.remove(self.manifest)
        self.assertTrue(self.vo.exists())

    def test_other_binaries_and_symlinks_are_not_candidates(self):
        (self.old / "Current.vo").write_text("keep")
        (self.old / "CslibLink.vo").symlink_to(self.vo)
        self.assertEqual([p["path"] for p in cleanup.candidates()], [str(self.vo)])


if __name__ == "__main__":
    unittest.main()
