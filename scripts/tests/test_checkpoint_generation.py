"""Representation changes create new chains; old evidence is never relabelled."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import checkpoint_generation as generation
import run_chunked_import as chunks


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.foundation = self.file("work/old-foundation/Lean.vo", "old foundation")
        self.file("work/old-foundation/Lean.v", "foundation source")
        self.plugin = self.file("_worktrees/rocq-lean-import/compact-peano-importer-current/src/lean_import.cmxs", "plugin")
        self.worker = self.file("worker", "worker")
        self.export = self.file("work/uint32-shift-repro/UIntShift.lean-export", "record\n" * 9)
        for name in ("run-memory-guarded", "run-checkpoint-atomic", "run-sealed-checkpoint"):
            self.file("work/" + name + ".sh", "guard")
        for module, name, value in ((chunks, "ROOT", self.root), (generation, "ROOT", self.root),
                                     (generation, "PLUGIN", self.plugin), (chunks, "WORKER", self.worker),
                                     (chunks, "KERNEL", self.root / "kernel"),
                                     (generation, "STDLIB", self.root / "stdlib")):
            p = patch.object(module, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.seed = self.file("work/old-chain/Prefix.vo", "historical checkpoint")
        self.file("work/old-chain/Prefix.v", "historical source")
        self.old = self.root / "old-plan"
        chunks.prepare(self.export, self.old, "Example", start=4, seed=self.seed)
        self.plan_path, self.smoke = generation.create(self.root / "new-generation", self.old / "plan.json", self.foundation)
        self.plan = chunks.load_plan(self.plan_path)

    def file(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_restart_starts_at_one_without_the_historical_seed(self):
        self.assertIsNone(self.plan["seed"])
        self.assertEqual(self.plan["chunks"][0]["start"], 1)
        self.assertEqual(self.plan["interval"], 2_000_000)
        self.assertEqual(self.seed.read_text(), "historical checkpoint")
        self.assertIsNotNone(chunks.load_plan(self.old / "plan.json")["seed"])

    def test_foundation_is_frozen_not_overwritten(self):
        profile = chunks.generation_toolchain(self.plan)
        frozen = Path(profile["foundation"])
        self.assertNotEqual(frozen, self.foundation)
        self.assertEqual(frozen.read_bytes(), self.foundation.read_bytes())
        self.foundation.write_text("another candidate")
        self.assertEqual(frozen.read_text(), "old foundation")
        chunks.preflight(self.plan)

    def test_new_representation_does_not_consult_legacy_pin(self):
        with patch.object(chunks.subprocess, "run") as run:
            chunks.preflight(self.plan)
        run.assert_not_called()

    def test_changed_importer_cannot_reuse_generation(self):
        self.plugin.write_text("changed representation")
        with self.assertRaises(chunks.Refused):
            chunks.preflight(self.plan)

    def test_worker_migration_requires_explicit_tested_handoff(self):
        self.worker.write_text("worker v2")
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(chunks.Refused):
                chunks.preflight(self.plan)
        with patch.dict(os.environ, {"ROCQ_APPROVED_WORKER_SHA256": chunks.sha(self.worker)}):
            chunks.preflight(self.plan)

    def test_new_manifest_cannot_be_rewritten_to_match_changes(self):
        manifest = Path(self.plan["toolchain"]["path"])
        manifest.write_text("{}")
        with self.assertRaises(chunks.Refused):
            chunks.preflight(self.plan)

    def test_generation_rejects_historical_seed(self):
        self.plan["seed"] = {"path": str(self.seed)}
        with self.assertRaises(chunks.Refused):
            chunks.generation_toolchain(self.plan)

    def test_compile_uses_new_foundation_without_old_checkpoint_loadpath(self):
        attempt = self.root / "attempt"
        attempt.mkdir()
        module = self.plan["chunks"][0]["module"]
        with patch.object(chunks.subprocess, "run", return_value=Mock(returncode=0)) as run:
            chunks.compile_module(self.plan_path.parent, module, attempt, False, self.root / "unused")
        command = run.call_args.args[0]
        self.assertNotIn(str(chunks.OLD_RUN), command)
        self.assertIn(str(Path(chunks.generation_toolchain(self.plan)["foundation"]).parent), command)

    def test_existing_generation_is_not_overwritten(self):
        with self.assertRaises(FileExistsError):
            generation.create(self.root / "new-generation", self.old / "plan.json", self.foundation)

    def test_fixed_suite_includes_fresh_prefixes_and_all_original_cases(self):
        self.assertEqual(sum(len(v.split()) for v in generation.REGRESSIONS.values()) + len(generation.IMPORTER_TESTS), 58)
        for group in list(generation.REGRESSIONS)[:6]:
            self.assertTrue(generation.REGRESSIONS[group].startswith("Prefix "))
        self.assertEqual(generation.REGRESSIONS["nat-bool-source-repro"].split(),
                         "Fresh Prefix Target Reload Adjacent BooleanRegistration ComparisonControls".split())


class SourceStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stage = self.root / "staged"
        patcher = patch.object(generation, "ROOT", self.root)
        patcher.start()
        self.addCleanup(patcher.stop)

    def file(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_load_sources_keep_paths_without_old_compiled_artifacts(self):
        wrapper = self.file("work/repro/Test.v", 'Load "../../_worktrees/kernel/check.v".\n')
        dependency = self.file("_worktrees/kernel/check.v", 'Load "../other/control".\n')
        control = self.file("work/other/control.v", "Check nat.\n")
        self.file("_worktrees/kernel/check.vo", "old checkpoint")
        destination = self.stage / "work/repro/Test.v"
        generation.stage_source(wrapper, destination, self.stage)
        self.assertEqual(destination.read_bytes(), wrapper.read_bytes())
        self.assertEqual((self.stage / "_worktrees/kernel/check.v").read_bytes(), dependency.read_bytes())
        self.assertEqual((self.stage / "work/other/control.v").read_bytes(), control.read_bytes())
        self.assertFalse(list(self.stage.rglob("*.vo")))

    def test_loaded_sources_are_in_protected_inputs(self):
        wrapper = self.file("work/repro/Test.v", 'Load "../other/control.v".\n')
        dependency = self.file("work/other/control.v", "Check nat.\n")
        with patch.object(generation, "REGRESSIONS", {"repro": "Test"}), \
                patch.object(generation, "IMPORTER_TESTS", []), \
                patch.object(generation, "IMPORTER", self.root / "importer"):
            self.assertIn(dependency, generation.regression_inputs())
        self.assertEqual(set(generation.source_inputs(wrapper)), {wrapper, dependency})

    def test_missing_load_is_rejected_before_compilation(self):
        wrapper = self.file("work/repro/Test.v", 'Load "Missing.v".\n')
        with self.assertRaises(FileNotFoundError):
            generation.source_inputs(wrapper)

    def test_absolute_load_is_rejected(self):
        wrapper = self.file("work/repro/Test.v", 'Load "/outside/check.v".\n')
        with self.assertRaisesRegex(chunks.Refused, "must be relative"):
            generation.source_inputs(wrapper)

    def test_staging_escape_is_rejected(self):
        wrapper = self.file("work/repro/Test.v", 'Load "../../check.v".\n')
        self.file("check.v", "Check nat.\n")
        with self.assertRaisesRegex(chunks.Refused, "escapes"):
            generation.stage_source(wrapper, self.stage / "Test.v", self.stage)

    def test_cycles_do_not_recurse_in_the_collector(self):
        wrapper = self.file("work/repro/Test.v", 'Load "Test.v".\n')
        self.assertEqual(generation.source_inputs(wrapper), [wrapper])


@unittest.skipUnless(os.environ.get("GENERATION_SYSTEMD_TEST") == "1", "Opt-in guarded Rocq generation smoke")
class GenerationSystemdSmoke(unittest.TestCase):
    def test_new_chain_save_reload_and_resume_with_actual_rocq(self):
        # Tiny existing fixture, not a full library. One 2 GiB worker at a time.
        directory = Path(tempfile.mkdtemp(prefix="generation-smoke-", dir=chunks.ROOT / "work"))
        fixture = chunks.ROOT / "work/cslib-v2/checkpoint-compact-smoke.lean-export"
        chunks.prepare(fixture, directory / "old", "Small", memory_mib=2048)
        plan_path, _ = generation.create(directory / "generation", directory / "old/plan.json",
                                         chunks.FOUNDATION / "Lean.vo")
        profile = chunks.load_plan(plan_path)["toolchain"]["path"]
        chunks.prepare(fixture, directory / "tiny", "GenerationSmoke", interval=4,
                       memory_mib=2048, toolchain=Path(profile))
        plan_path = directory / "tiny/plan.json"
        for attempt in ("first", "resume"):
            unit = "rocq-generation-smoke-" + str(os.getpid()) + "-" + attempt + ".service"
            result = subprocess.run([
                "systemd-run", "--user", "--wait", "--pipe", "--collect", "--unit=" + unit,
                "--property=RuntimeMaxSec=90", "--property=MemoryMax=512M", "--property=MemorySwapMax=0",
                "/usr/bin/env", "ROCQ_MEMORY_OWNER_SERVICE=" + unit,
                sys.executable, str(chunks.SCRIPT), "run", "--plan", str(plan_path),
                "--attempt", str(directory / attempt)], capture_output=True, text=True, timeout=110)
            self.assertEqual(result.returncode, 0, str(directory) + "\n" + result.stdout + result.stderr)
        chunks.verify_complete(plan_path)
        print("Actual generation smoke evidence:", directory)


if __name__ == "__main__":
    unittest.main()
