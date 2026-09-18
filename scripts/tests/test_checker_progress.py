import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'checker_progress.py'
spec = importlib.util.spec_from_file_location('checker_progress', SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class ProgressTests(unittest.TestCase):
    def test_progress_deadline_not_whole_file(self):
        p = guard.Progress('M', 30, 0)
        for i in range(1, 11):
            self.assertFalse(p.expired(i * 20))
            p.feed(f'  checking cst:M.c{i}\n'.encode(), i * 20)
        self.assertFalse(p.expired(229))
        self.assertTrue(p.expired(230))
        self.assertEqual(p.count, 10)

    def test_noise_other_modules_and_duplicate_do_not_reset(self):
        p = guard.Progress('M', 30, 0)
        p.feed(b'  checking cst:M.a\n', 1)
        for line in (b'memory guard: alive\n', b'  checking cst:Other.b\n',
                     b'  checking cst:M.a\n', b'diagnostic: checking cst:M.b\n',
                     b'  checking cst:MM.b\n'):
            p.feed(line, 25)
        self.assertTrue(p.expired(31))
        self.assertEqual(p.count, 1)

    def test_split_lines_and_bounded_diagnostics(self):
        p = guard.Progress('M', 30, 0)
        for chunk in (b'  check', b'ing cst:M.a', b'\r', b'\n'):
            p.feed(chunk, 2)
        self.assertEqual(p.current, 'M.a')
        p.feed(b'x' * 70000, 3)
        self.assertEqual(p.pending, b'')
        p.feed(b'  checking cst:M.fake\n', 4)
        self.assertEqual(p.current, 'M.a')
        p.feed(b'  checking cst:M.b\n', 5)
        self.assertEqual(p.current, 'M.b')

    def test_invalid_policy(self):
        for seconds in (0, -1, float('inf'), float('nan')):
            with self.assertRaises(ValueError):
                guard.Progress('M', seconds, 0)
        with self.assertRaises(ValueError):
            guard.Progress('M.*', 30, 0)

    def run_child(self, script, seconds=1):
        with tempfile.TemporaryDirectory(prefix='rocq-checker-progress-test-') as temp:
            output = io.BytesIO()
            record = guard.run([sys.executable, '-u', '-c', script], 'M', seconds,
                               Path(temp) / 'progress.json', output, grace=0.1)
            return record, output.getvalue()

    def test_real_process_long_total_with_progress(self):
        result, output = self.run_child('import time\nfor i in range(5):\n'
            ' print("  checking cst:M.c" + str(i), flush=True)\n time.sleep(0.3)', 1)
        self.assertEqual(result['exit_code'], 0)
        self.assertGreater(result['elapsed_seconds'], 1)
        self.assertEqual(result['declarations_started'], 5)
        self.assertIn(b'M.c4', output)

    def test_real_stall_and_noise_timeout(self):
        result, _ = self.run_child('import time\nprint("  checking cst:M.a", flush=True)\n'
            'while True:\n print("noise", flush=True)\n time.sleep(0.02)', 0.3)
        self.assertEqual(result['exit_code'], 124)
        self.assertEqual(result['phase'], 'timeout')

    def test_startup_and_finalization_timeouts(self):
        for script in ('import time; time.sleep(10)',
                       'import time; print("  checking cst:M.a", flush=True); time.sleep(10)'):
            self.assertEqual(self.run_child(script, 0.2)[0]['exit_code'], 124)

    def test_failure_is_not_hidden_and_success_needs_progress(self):
        for script, expected in (('print("  checking cst:M.a"); raise SystemExit(7)', 7),
                                 ('print("success without checking")', 65)):
            self.assertEqual(self.run_child(script)[0]['exit_code'], expected)

    def test_term_ignoring_child_is_reaped(self):
        result, _ = self.run_child('import signal,time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                                  'print("  checking cst:M.a",flush=True)\ntime.sleep(10)', 0.3)
        self.assertEqual(result['exit_code'], 124)
        self.assertLess(result['elapsed_seconds'], 3)


if __name__ == '__main__':
    unittest.main()
