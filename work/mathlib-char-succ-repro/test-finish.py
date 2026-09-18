#!/usr/bin/env python3
"""No compiler or service is launched by these supervisor control-flow tests."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('finish', Path(__file__).with_name('finish.py'))
finish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(finish)


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        for name, value in [('HERE', self.directory), ('ROOT', self.directory),
                            ('STATE', self.directory / 'finish-status.json')]:
            patcher = patch.object(finish, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(finish.sys, 'argv', ['finish.py', '--worker-sha', 'worker',
                                                  '--checker-sha', 'checker'])
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = patch.object(finish, 'pin_inputs', return_value={})
        patcher.start()
        self.addCleanup(patcher.stop)

    def run_steps(self, codes, active='active'):
        replies = [subprocess.CompletedProcess([], code) for code in codes]
        if all(code == 0 for code in codes):
            replies.append(subprocess.CompletedProcess([], 0,
                stdout=f'ActiveState={active}\nSubState=running\nResult=success\n'))
        with patch.object(finish, 'wait_for_memory') as admission, \
             patch.object(finish.subprocess, 'run', side_effect=replies) as run:
            result = finish.main()
            if len(codes) == 3:
                self.assertEqual(admission.call_args.args[0], 16384)
            else:
                admission.assert_not_called()
            return result, run.call_args_list

    def test_validation_failure_never_promotes(self):
        result, calls = self.run_steps([1])
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 1)
        self.assertFalse(json.loads(finish.STATE.read_text())['launch_attempted'])

    def test_promotion_failure_never_launches(self):
        result, calls = self.run_steps([0, 1])
        self.assertEqual(result, 1)
        self.assertEqual(len(calls), 2)
        self.assertIn('--validate-only', calls[-1].args[0])

    def test_success_launches_once_after_all_checks(self):
        result, calls = self.run_steps([0, 0, 0])
        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 4)
        self.assertIn('--worker-sha', calls[0].args[0])
        self.assertIn('--validate-only', calls[1].args[0])
        self.assertNotIn('--validate-only', calls[2].args[0])
        self.assertEqual(calls[3].args[0][0], 'systemctl')
        self.assertFalse(json.loads(finish.STATE.read_text())['monitoring'])

    def test_failed_startup_is_not_reported_as_running(self):
        result, _ = self.run_steps([0, 0, 0], active='failed')
        self.assertEqual(result, 1)
        self.assertEqual(json.loads(finish.STATE.read_text())['phase'],
                         'production_startup_failed')

    def test_existing_attempt_is_not_restarted(self):
        finish.STATE.touch()
        with self.assertRaises(RuntimeError):
            finish.main()

    def test_stage_scheduler_handles_memory_admission(self):
        with patch.object(finish, 'wait_for_memory', side_effect=AssertionError('Use stage admission')), \
             patch.object(finish.subprocess, 'run',
                          return_value=subprocess.CompletedProcess([], 1)):
            self.assertEqual(finish.main(), 1)

    def test_candidate_change_before_validation_stops_launch(self):
        with patch.object(finish, 'pin_inputs', return_value={Path('candidate'): 'old'}), \
             patch.object(finish, 'digest', return_value='new'), \
             patch.object(finish.subprocess, 'run') as run:
            self.assertEqual(finish.main(), 1)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
