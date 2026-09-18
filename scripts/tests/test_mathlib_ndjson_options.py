"""Run configuration checks without launching a compiler or model."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mathlib_ndjson_loop as driver


class OptionsTests(unittest.TestCase):
    def test_resume_matches_five_million_plan(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = root / "checkpoints/plan.json"
            path.parent.mkdir()
            path.write_text(json.dumps({"interval": 5_000_000, "memory_mib": 16384,
                                        "line_timeout": 1800}))
            self.assertEqual(driver.prepare(root, False, 16384, 5_000_000, 1800), path)
            with self.assertRaisesRegex(driver.chunks.Refused, "different"):
                driver.prepare(root, False, 16384)

    def test_invalid_interval_fails_before_preparation(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(driver.chunks.Refused):
                driver.prepare(Path(tmp), False, 16384, 0)


if __name__ == "__main__":
    unittest.main()
