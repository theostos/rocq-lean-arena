import json
from pathlib import Path
import tempfile
import unittest

from report import summarize, TARGET


def snapshot(stage, cpu, query, build):
    return f"[dependency profile] stage={stage} cpu={cpu} query_cpu={query} build_cpu={build}\n"


class ReportTest(unittest.TestCase):
    def report(self, log):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "run.log").write_text(log)
            (directory / "result.json").write_text('{"exit_code":1}')
            summarize(directory)
            return json.loads((directory / "measurement.json").read_text())

    def test_timeout_bounds(self):
        result = self.report(snapshot("start", 0, 0, 0) + snapshot("sample", 10, 2, 1)
            + f"[declare start] {TARGET} instance 0 cpu=10.200\n"
            + snapshot("exit", 1810.200, 7, 3))
        self.assertTrue(result["complete"])
        self.assertAlmostEqual(result["target_cpu_seconds"], 1800)
        query = result["bounds"]["query_cpu"]
        self.assertLessEqual(query["lower_seconds"], 4.8)
        self.assertGreaterEqual(query["upper_seconds"], 5.0)
        self.assertLess(query["upper_percent"], 0.28)

    def test_missing_exit_is_not_a_measurement(self):
        result = self.report(snapshot("start", 0, 0, 0)
            + f"[declare start] {TARGET} instance 0 cpu=10.200\n")
        self.assertFalse(result["complete"])

    def test_exclude_post_target_work(self):
        result = self.report(snapshot("start", 0, 0, 0) + snapshot("sample", 10, 2, 1)
            + f"[declare start] {TARGET} instance 0 cpu=10.200\n"
            + snapshot("sample", 20, 3, 1.5)
            + f"[declare done] {TARGET} instance 0 cpu=20.500\n"
            + snapshot("exit", 100, 50, 25))
        self.assertLess(result["bounds"]["query_cpu"]["upper_seconds"], 1.51)


if __name__ == "__main__":
    unittest.main()
