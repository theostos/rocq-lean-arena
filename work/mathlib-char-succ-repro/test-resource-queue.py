#!/usr/bin/env python3
"""No real jobs, sleeps, or production files are used by these tests."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import resource_queue as queue


class QueueTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.stage = Path(temporary.name) / 'fresh-diagnostic'
        self.stage.mkdir()
        self.log = self.stage / 'run.log'
        self.record = self.stage / 'result.json'
        self.log.write_text('memory guard: refusing launch: MemAvailable=100 KiB; '
            'need at least reserve(3145728) + budget(16777216) = 19922944 KiB\n')
        self.record.write_text(json.dumps({'exit_code': 75}))

    def archive(self, code=75):
        return queue.archive_unstarted(code, self.log, self.record, fresh_directory=self.stage)

    def test_wait_preserves_16_gib_plus_3_gib_reserve(self):
        report = Mock()
        with patch.object(queue, 'available_kib', side_effect=[18*1024**2, 19*1024**2]), \
             patch.object(queue.time, 'sleep') as sleep:
            queue.wait_for_memory(16384, report)
        sleep.assert_called_once_with(15)
        self.assertEqual(report.call_args.kwargs['required_kib'], 19*1024**2)

    def test_small_check_can_start_before_large_replay(self):
        report = Mock()
        with patch.object(queue, 'available_kib', return_value=12*1024**2), \
             patch.object(queue.time, 'sleep') as sleep:
            queue.wait_for_memory(8192, report)
        sleep.assert_not_called()
        report.assert_not_called()

    def test_invalid_budget_rejected(self):
        for value in [0, 1023, 16385, 20480]:
            with self.assertRaises(ValueError):
                queue.wait_for_memory(value, Mock())

    def test_refused_compile_preserved_for_retry(self):
        original = self.log.read_text()
        archived, = self.archive()
        self.assertFalse(self.stage.exists())
        self.assertEqual((Path(archived)/'run.log').read_text(), original)

    def test_compiler_failure_never_retried(self):
        for code in [1, 124, 137, -11]:
            self.assertIsNone(self.archive(code))
        self.assertTrue(self.stage.exists())

    def test_exit_75_after_admission_never_retried(self):
        self.log.write_text(self.log.read_text() + 'memory guard: admitted with MemAvailable=200 KiB\n')
        self.assertIsNone(self.archive())

    def test_lock_conflict_is_not_memory_admission(self):
        self.log.write_text('memory guard: another heavyweight run holds lock\n')
        self.assertIsNone(self.archive())

    def test_record_must_confirm_refusal(self):
        self.record.write_text(json.dumps({'exit_code': 0}))
        self.assertIsNone(self.archive())

    def test_existing_proof_never_archived(self):
        (self.stage/'Proof.vo').write_bytes(b'proof')
        self.assertIsNone(self.archive())

    def test_checker_retry_preserves_compiled_artifact(self):
        artifact = self.stage/'Proof.vo'
        artifact.write_bytes(b'proof')
        archived = queue.archive_unstarted(75, self.log, self.record)
        self.assertEqual(len(archived), 2)
        self.assertEqual(artifact.read_bytes(), b'proof')
        self.assertFalse(self.log.exists())
        self.assertFalse(self.record.exists())


if __name__ == '__main__':
    unittest.main()
