"""Exercise the real guards' proc reader, without launching guarded workloads."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
GUARDS = (
    ROOT / "work/run-memory-guarded.sh",
    ROOT / "checkers/rocq-lean-import/scripts/run-memory-guarded.sh",
)


@unittest.skipUnless(Path("/proc/self/root").is_dir(), "requires Linux procfs")
class ProcLivenessTests(unittest.TestCase):
    def run_probe(self, guard: Path, stat: str | None, *, disappear=False):
        source = guard.read_text(encoding="utf-8")
        match = re.search(r"(?ms)^pid_is_live\(\) \{\n.*?^\}", source)
        self.assertIsNotNone(match, "guard's liveness function was not found")
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "stat"
            if stat is not None:
                fixture.write_text(stat, encoding="utf-8")
            # /proc/self/root permits an owned fixture without replacing the
            # function's real /proc path or racing any actual user process.
            environment = {
                **os.environ,
                "FAKE_PID": f"self/root{directory}",
                "STAT_FIXTURE": str(fixture),
                "DISAPPEAR": str(int(disappear)),
            }
            script = "set -Eeuo pipefail\nset -T\n" + match[0] + r'''
if [[ $DISAPPEAR == 1 ]]; then
  # Remove the fixture just before the old assignment or the new atomic read.
  # With the old code this is after its successful readability check.
  trap 'case "$BASH_COMMAND" in stat_line=\$\(*|mapfile\ *)
    rm -f -- "$STAT_FIXTURE" ;; esac' DEBUG
fi
if pid_is_live "$FAKE_PID"; then result=live; else result=gone; fi
trap - DEBUG
printf '%s\n' "$result"
'''
            return subprocess.run(
                ["bash", "-c", script], env=environment,
                text=True, capture_output=True, timeout=5,
            )

    def test_disappearance_does_not_exit_supervisor(self):
        for guard in GUARDS:
            with self.subTest(guard=guard):
                result = self.run_probe(guard, "123 (worker) S 1 2 3\n", disappear=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "gone\n")
                self.assertEqual(result.stderr, "")

    def test_process_states_and_multiline_names(self):
        cases = (
            (None, "gone"),
            ("", "gone"),
            ("123 (worker) S 1 2 3\n", "live"),
            ("123 (worker) Z 1 2 3\n", "gone"),
            ("123 (worker) X 1 2 3\n", "gone"),
            ("123 (a ) name\nwith newline) R 1 2 3\n", "live"),
            ("123 (a ) name\nwith newline) Z 1 2 3\n", "gone"),
        )
        for guard in GUARDS:
            for stat, expected in cases:
                with self.subTest(guard=guard, stat=stat):
                    result = self.run_probe(guard, stat)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, expected + "\n")
                    self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
