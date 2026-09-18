#!/usr/bin/env python3
"""Small fail-closed tests; no Rocq process or real checkpoint is changed."""
import copy
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import consumer_toolchain as migration


class ConsumerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='rocq-consumer-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.producer, self.consumer = self.root / 'producer', self.root / 'consumer'
        for directory in (self.producer, self.consumer):
            (directory / 'src').mkdir(parents=True)
            for name, text in {'lean.ml': 'let importer = 1', 'Lean.v': 'Inductive U := u.',
                               'dune': '(library)', 'META': 'runtime'}.items():
                (directory / 'src' / name).write_text(text)
            (directory / 'src/lean_import.cmxs').write_text(directory.name + '-binary')
        self.worker = self.root / 'worker'
        self.worker.write_text('approved worker')
        self.evidence = self.root / 'validation.json'
        self.evidence.write_text('{"passed": true}')
        self.profile_path = self.root / 'producer.json'
        self.profile_path.write_text('immutable producer profile')
        self.plan = {'memory_mib': 16384, 'interval': 5000000, 'line_timeout': 1800,
                     'toolchain': {'path': str(self.profile_path),
                                  'sha256': migration.chunks.sha(self.profile_path)}}
        self.plan_path = self.root / 'plan.json'
        self.plan_path.write_text(json.dumps(self.plan))
        self.profile = {'format': 1, 'importer': str(self.producer),
                        'foundation': 'unchanged foundation', 'worker_sha256': 'historical',
                        'inputs': {str(p): migration.chunks.sha(p) for p in
                                   (self.producer / 'src/lean_import.cmxs', self.producer / 'src/META')}}

        def producer_loader(plan):
            if migration.chunks.sha(self.profile_path) != plan['toolchain']['sha256']:
                raise migration.chunks.Refused('producer profile changed')
            return copy.deepcopy(self.profile)

        self.original_loader = producer_loader
        for item in (patch.object(migration.chunks, 'WORKER', self.worker),
                     patch.object(migration.chunks, 'load_plan', lambda p: json.loads(p.read_text())),
                     patch.object(migration.chunks, 'generation_toolchain', producer_loader)):
            item.start()
            self.addCleanup(item.stop)
        self.certificate = migration.make_certificate(self.plan_path, self.consumer,
            {str(self.evidence): migration.chunks.sha(self.evidence)})
        self.certificate_path = self.root / 'consumer.json'
        self.save_certificate()

    def save_certificate(self):
        self.certificate_path.write_text(json.dumps(self.certificate))
        self.digest = migration.chunks.sha(self.certificate_path)

    def installed(self):
        return migration.installed_consumer(self.certificate_path, self.digest)

    def assert_refused(self):
        with self.assertRaises(migration.chunks.Refused):
            with self.installed():
                pass
        self.assertIs(migration.chunks.generation_toolchain, self.original_loader)

    def test_immutable_producer_and_additive_consumer(self):
        before = copy.deepcopy(self.profile)
        with self.installed() as (path, plan):
            self.assertEqual(path, self.plan_path)
            combined = migration.chunks.generation_toolchain(plan)
            self.assertEqual(combined['importer'], str(self.consumer))
            self.assertEqual(combined['foundation'], self.profile['foundation'])
            self.assertEqual(combined['inputs'][str(self.certificate_path)], self.digest)
            for p, h in before['inputs'].items():
                self.assertEqual(combined['inputs'][p], h)
            self.assertIn(str(self.consumer / 'src/lean_import.cmxs'), combined['inputs'])
        self.assertEqual(self.profile, before)
        self.assertIs(migration.chunks.generation_toolchain, self.original_loader)

    def test_changed_consumer_source(self):
        (self.consumer / 'src/lean.ml').write_text('changed semantics')
        self.assert_refused()

    def test_extra_source(self):
        (self.consumer / 'src/extra.ml').write_text('unbound extra source')
        self.assert_refused()

    def test_changed_consumer_binary(self):
        (self.consumer / 'src/lean_import.cmxs').write_text('other binary')
        self.assert_refused()

    def test_changed_producer_binary(self):
        (self.producer / 'src/lean_import.cmxs').write_text('other producer')
        self.assert_refused()

    def test_changed_producer_profile(self):
        self.profile_path.write_text('changed producer profile')
        self.assert_refused()

    def test_changed_worker(self):
        self.worker.write_text('unapproved worker')
        self.assert_refused()

    def test_changed_certificate(self):
        self.certificate_path.write_text('{}')
        self.assert_refused()

    def test_missing_runtime_pin(self):
        del self.certificate['inputs'][str(self.consumer / 'src/lean_import.cmxs')]
        self.save_certificate()
        self.assert_refused()

    def test_changed_evidence(self):
        self.evidence.write_text('{"passed": false}')
        self.assert_refused()

    def test_missing_evidence_pin(self):
        del self.certificate['inputs'][str(self.evidence)]
        self.save_certificate()
        self.assert_refused()

    def test_changed_plan(self):
        self.plan_path.write_text('{"different": true}')
        self.assert_refused()

    def test_foreign_plan_and_restore_on_exception(self):
        with self.assertRaises(migration.chunks.Refused):
            with self.installed():
                migration.chunks.generation_toolchain({'foreign': True})
        self.assertIs(migration.chunks.generation_toolchain, self.original_loader)

    def test_recheck_at_each_profile_read(self):
        with self.installed():
            self.worker.write_text('changed after installation')
            with self.assertRaises(migration.chunks.Refused):
                migration.chunks.generation_toolchain(self.plan)

    def test_missing_validation(self):
        with self.assertRaises(migration.chunks.Refused):
            migration.make_certificate(self.plan_path, self.consumer, {})

    def launch_mock(self, error=False):
        checking = SimpleNamespace(IMPORTER=self.producer)
        calls = []

        def run(*args):
            self.assertEqual(checking.IMPORTER, self.consumer)
            self.assertEqual(migration.chunks.generation_toolchain(self.plan)['importer'],
                             str(self.consumer))
            calls.append(args)
            if error:
                raise RuntimeError('mock run failure')
            return 23

        loop = SimpleNamespace(direct=SimpleNamespace(checking=checking), run=run)
        parsed = SimpleNamespace(certificate=self.certificate_path, sha256=self.digest)
        with patch.dict(migration.sys.modules, {'mathlib_ndjson_loop': loop}), \
             patch.dict(migration.os.environ, {}, clear=True), \
             patch.object(migration.argparse.ArgumentParser, 'parse_args', return_value=parsed):
            if error:
                with self.assertRaisesRegex(RuntimeError, 'mock run failure'):
                    migration.main()
            else:
                self.assertEqual(migration.main(), 23)
        self.assertEqual(calls, [(self.plan_path.parent.parent, False, 16384, 5000000, 1800)])
        self.assertEqual(checking.IMPORTER, self.producer)
        self.assertIs(migration.chunks.generation_toolchain, self.original_loader)

    def test_launch_uses_consumer_and_preserves_run_policy(self):
        self.launch_mock()

    def test_launch_restores_configuration_on_failure(self):
        self.launch_mock(error=True)


if __name__ == '__main__':
    unittest.main()
