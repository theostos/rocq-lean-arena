"""Test service-binding validation only; no service, guard workload or Rocq starts."""

import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
GUARDS = (
    ROOT / "work/run-memory-guarded.sh",
    ROOT / "checkers/rocq-lean-import/scripts/run-memory-guarded.sh",
)


class ServiceOwnerTests(unittest.TestCase):
    def probe(self, guard, owner, cgroup):
        source = guard.read_text(encoding="utf-8")
        start = source.index("  owner_args=()\n")
        end = source.index("\n  script_path=", start)
        block = textwrap.dedent(source[start:end])
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "cgroup"
            fixture.write_text(cgroup, encoding="utf-8")
            block = block.replace("/proc/self/cgroup", shlex.quote(str(fixture)))
            script = (
                'set -Eeuo pipefail\ndie() { echo "$*" >&2; exit 78; }\n'
                + block
                + '\nfor arg in "${owner_args[@]}"; do printf "%s\\n" "$arg"; done\n'
            )
            env = dict(os.environ)
            env.pop("ROCQ_MEMORY_OWNER_SERVICE", None)
            if owner is not None:
                env["ROCQ_MEMORY_OWNER_SERVICE"] = owner
            return subprocess.run(
                ["bash", "-c", script], env=env, text=True,
                capture_output=True, timeout=5,
            )

    def test_only_bind_the_actual_enclosing_service(self):
        cases = (
            (None, "", 0, ""),
            ("", "", 0, ""),
            ("check.service", "0::/user.slice/app.slice/check.service\n", 0,
             "--property=BindsTo=check.service\n--property=After=check.service\n"),
            ("other.service", "0::/user.slice/check.service\n", 78, ""),
            ("check.service --help", "0::/user.slice/check.service\n", 78, ""),
            ("check.scope", "0::/user.slice/check.scope\n", 78, ""),
            ("check.service", "1:memory:/check.service\n", 78, ""),
            ("check.service", "0::/check.service/delegated\n", 78, ""),
        )
        for guard in GUARDS:
            for owner, cgroup, status, output in cases:
                with self.subTest(guard=guard, owner=owner, cgroup=cgroup):
                    result = self.probe(guard, owner, cgroup)
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertEqual(result.stdout, output)
                    if status:
                        self.assertTrue(result.stderr)


if __name__ == "__main__":
    unittest.main()
