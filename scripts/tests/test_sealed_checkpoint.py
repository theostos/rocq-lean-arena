"""Checkpoint reuse/transaction tests; no Rocq process is launched."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SealedCheckpointTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.runner = self.path / "run-sealed-checkpoint.sh"
        shutil.copyfile(ROOT / "work/run-sealed-checkpoint.sh", self.runner)
        self.source = self.path / "Prefix.v"
        self.source.write_text("source\n")
        self.dependency = self.path / "dependency"
        self.dependency.write_text("original\n")
        self.manifest = self.path / "inputs.sha256"
        digest = hashlib.sha256(self.dependency.read_bytes()).hexdigest()
        self.manifest.write_text(f"{digest}  {self.dependency}\n")
        self.artifact = self.source.with_suffix(".vo")
        self.seal = self.source.with_suffix(".seal")
        self.calls = self.path / "calls"
        (self.path / "run-checkpoint-atomic.sh").write_text(
            '#!/usr/bin/env bash\nset -eu\n'
            'printf "call\\n" >> "$MOCK_CALLS"\n'
            'if [[ ${MOCK_FAIL:-0} == 1 ]]; then exit 42; fi\n'
            'printf "checked artifact\\n" > "${1%.v}.vo"\n'
            'if [[ ${MOCK_CHANGE:-0} == 1 ]]; then '
            'printf "changed\\n" >> "$1"; fi\n'
        )

    def run_checkpoint(self, **extra):
        env = {**os.environ, "ROCQ_CHECKPOINT_INPUTS_FILE": str(self.manifest),
               "MOCK_CALLS": str(self.calls), **extra}
        return subprocess.run(["bash", str(self.runner), str(self.source),
                               "--", "unused-compiler"], env=env,
                              capture_output=True, text=True, timeout=10)

    def assert_ok(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_save_and_reuse_without_recompilation(self):
        self.assert_ok(self.run_checkpoint())
        self.assertTrue(self.seal.is_dir())
        self.assert_ok(self.run_checkpoint())
        self.assertEqual(self.calls.read_text(), "call\n")

    def test_failed_compile_does_not_seal_and_can_retry(self):
        self.assertEqual(self.run_checkpoint(MOCK_FAIL="1").returncode, 42)
        self.assertFalse(self.artifact.exists())
        self.assertFalse(self.seal.exists())
        self.assert_ok(self.run_checkpoint())

    def test_refuse_changed_dependency(self):
        self.assert_ok(self.run_checkpoint())
        original = self.artifact.read_bytes()
        self.dependency.write_text("changed\n")
        self.assertNotEqual(self.run_checkpoint().returncode, 0)
        self.assertEqual(self.artifact.read_bytes(), original)
        self.assertEqual(self.calls.read_text(), "call\n")

    def test_refuse_changed_source(self):
        self.assert_ok(self.run_checkpoint())
        self.source.write_text("different source\n")
        self.assertNotEqual(self.run_checkpoint().returncode, 0)

    def test_refuse_corrupt_artifact(self):
        self.assert_ok(self.run_checkpoint())
        self.artifact.write_text("corrupted\n")
        self.assertNotEqual(self.run_checkpoint().returncode, 0)
        self.assertEqual(self.artifact.read_text(), "corrupted\n")

    def test_refuse_unsealed_artifact(self):
        self.artifact.write_text("unknown producer\n")
        self.assertEqual(self.run_checkpoint().returncode, 65)
        self.assertFalse(self.calls.exists())

    def test_refuse_missing_artifact(self):
        self.assert_ok(self.run_checkpoint())
        self.artifact.unlink()
        self.assertEqual(self.run_checkpoint().returncode, 65)
        self.assertEqual(self.calls.read_text(), "call\n")

    def test_refuse_input_change_during_compile(self):
        self.assertNotEqual(self.run_checkpoint(MOCK_CHANGE="1").returncode, 0)
        self.assertFalse(self.seal.exists())
        # A crash/change after atomic promotion must not bless an unsealed .vo.
        self.assertEqual(self.run_checkpoint().returncode, 65)

    def test_verify_current_inputs_also_when_reusing(self):
        self.assert_ok(self.run_checkpoint())
        self.manifest.write_text("0" * 64 + f"  {self.dependency}\n")
        self.assertNotEqual(self.run_checkpoint().returncode, 0)

    def test_refuse_competing_sealer(self):
        import fcntl
        with self.source.with_suffix(".seal.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.run_checkpoint().returncode, 75)
        self.assertFalse(self.calls.exists())


class CheckpointLauncherTests(unittest.TestCase):
    """Exercise stage selection with a fake compiler and no systemd/Rocq job."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.run = self.root / "work/cslib-full-fresh/runs/cslib-unit-fix"
        self.run.mkdir(parents=True)
        paths = ["work/uint32-not-repro/resume-cslib.sh",
                 "work/lrat-restore-repro/check-prefix15m.sh",
                 "work/run-sealed-checkpoint.sh"]
        paths += [f"work/cslib-full-fresh/runs/cslib-unit-fix/{s}.v" for s in
                  ("Prefix15M", "Reload15M", "Complete15M", "ReloadComplete15M")]
        for relative in paths:
            dest = self.root / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, dest)
        check = self.root / "work/unit-projection-repro/check-toolchain.sh"
        check.parent.mkdir(parents=True)
        check.write_text("exit 0\n")
        worker = self.root / "_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe"
        worker.parent.mkdir(parents=True)
        worker.write_text("mock worker\n")
        self.prefix = self.run / "Prefix.vo"
        self.prefix.write_text("unchanged 11M checkpoint\n")
        digest = hashlib.sha256(self.prefix.read_bytes()).hexdigest()
        for name in ("inputs.sha256", "prefix.sha256"):
            (self.run / name).write_text(f"{digest}  {self.prefix}\n")
        self.calls = self.root / "calls"
        (self.root / "work/run-checkpoint-atomic.sh").write_text(
            'set -eu\nstage=$(basename "$1" .v)\n'
            'printf "%s\\n" "$stage" >> "$MOCK_CALLS"\n'
            '[[ $stage != ${MOCK_FAIL_STAGE:-} ]] || exit 42\n'
            'printf "checked %s\\n" "$stage" > "${1%.v}.vo"\n'
        )

    def launch(self, *args, **extra):
        return subprocess.run(
            ["bash", str(self.root / "work/uint32-not-repro/resume-cslib.sh"),
             "--run", *args], capture_output=True, text=True, timeout=10,
            env={**os.environ, "MOCK_CALLS": str(self.calls), **extra})

    def test_checkpoint_only_then_resume_without_rebuilding_prefix(self):
        first = self.launch("--checkpoint-only")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["Prefix15M", "Reload15M"])
        self.assertFalse((self.run / "Complete15M.vo").exists())
        second = self.launch()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(self.calls.read_text().splitlines(),
                         ["Prefix15M", "Reload15M", "Reload15M", "Complete15M", "ReloadComplete15M"])
        self.assertEqual(self.prefix.read_text(), "unchanged 11M checkpoint\n")

    def test_failed_continuation_preserves_new_prefix_for_retry(self):
        self.assertEqual(self.launch(MOCK_FAIL_STAGE="Complete15M").returncode, 42)
        saved = (self.run / "Prefix15M.vo").read_bytes()
        self.assertTrue((self.run / "Prefix15M.seal").is_dir())
        self.assertFalse((self.run / "Complete15M.seal").exists())
        retry = self.launch()
        self.assertEqual(retry.returncode, 0, retry.stdout + retry.stderr)
        self.assertEqual((self.run / "Prefix15M.vo").read_bytes(), saved)
        self.assertEqual(self.calls.read_text().splitlines().count("Prefix15M"), 1)

    def test_failed_prefix_stops_before_continuation(self):
        self.assertEqual(self.launch(MOCK_FAIL_STAGE="Prefix15M").returncode, 42)
        self.assertEqual(self.calls.read_text().splitlines(), ["Prefix15M"])
        self.assertFalse((self.run / "Prefix15M.seal").exists())
        self.assertEqual(self.prefix.read_text(), "unchanged 11M checkpoint\n")

    def test_declared_ranges_are_contiguous(self):
        prefix = (self.run / "Prefix15M.v").read_text()
        complete = (self.run / "Complete15M.v").read_text()
        self.assertIn('" 11005951 15001016.', prefix)
        self.assertIn('" 15001016.', complete)
        self.assertIn("Require Import Prefix15M.", complete)


class CheckpointMigrationTests(unittest.TestCase):
    def setUp(self):
        CheckpointLauncherTests.setUp(self)
        self.checker = self.root / "work/lrat-restore-repro/check-prefix15m.sh"
        self.seal = self.run / "Prefix15M.seal"
        self.seal.mkdir()
        self.artifact = self.run / "Prefix15M.vo"
        self.artifact.write_text("historical checkpoint\n")
        worker = self.root / "_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe"
        launcher = self.root / "work/uint32-not-repro/resume-cslib.sh"
        check_toolchain = self.root / "work/unit-projection-repro/check-toolchain.sh"
        self.source = self.run / "Prefix15M.v"

        def row(path):
            return f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n"

        inputs = self.seal / "inputs.sha256"
        inputs.write_text("".join(map(row, (worker, launcher, check_toolchain, self.source))))
        artifacts = self.seal / "artifact.sha256"
        artifacts.write_text(row(self.artifact))
        # Replace only the two historical pins with hashes of this synthetic
        # fixture. The production checker, filtering policy and path checks run.
        self.checker.write_text(self.checker.read_text().replace(
            "77e16b17b8c8bc0477074f2c4cf65a9ef2a7ec01b634c26f526aab96410f5279",
            hashlib.sha256(inputs.read_bytes()).hexdigest()).replace(
            "756cd331b222276a1d95a98394f14165841ae0561160a9000ef29f8284f7dd18",
            hashlib.sha256(artifacts.read_bytes()).hexdigest()))
        worker.write_text("new pinned mock worker\n")
        launcher.write_text(launcher.read_text() + "\n# changed launcher\n")
        check_toolchain.write_text("# new worker pin checked here\nexit 0\n")

    def verify(self):
        return subprocess.run(["bash", str(self.checker)], capture_output=True,
                              text=True, timeout=10)

    def test_accept_only_reviewed_changes(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.artifact.read_text(), "historical checkpoint\n")

    def test_source_change_still_rejected(self):
        self.source.write_text("changed proof input\n")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_artifact_change_still_rejected(self):
        self.artifact.write_text("corrupt\n")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_unrecognized_history_gets_no_exception(self):
        with (self.seal / "inputs.sha256").open("a") as manifest:
            manifest.write("\n")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_current_toolchain_must_pass(self):
        (self.root / "work/unit-projection-repro/check-toolchain.sh").write_text("exit 78\n")
        self.assertEqual(self.verify().returncode, 78)


if __name__ == "__main__":
    unittest.main()
