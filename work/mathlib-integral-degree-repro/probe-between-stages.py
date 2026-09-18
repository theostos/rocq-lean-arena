#!/usr/bin/env python3
"""Serialize a diagnostic after a running segment without stopping its worker.

Only the validated queue parent is paused. Always release it on exit; an
independent systemd timer is a final safeguard if this coordinator disappears.
No production evidence is created by this diagnostic.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
QUEUE = 1389474
CHILD = 1471375
STAGE = HERE.parent / 'mathlib-etale-repro/original-etale-v8/result.json'
BINARY = HERE / 'checker.YgAPWMHL/recheck.exe'

def cmdline(pid):
    return Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')

def same_queue():
    try:
        args = cmdline(QUEUE)
        return (str(HERE.parent / 'mathlib-etale-repro/validate.py').encode() in args
                and b'etale-v8' in args)
    except FileNotFoundError:
        return False

def release(*_):
    if same_queue():
        os.kill(QUEUE, signal.SIGCONT)

def abort(signum, _frame):
    release()
    raise SystemExit(128 + signum)

def main():
    assert same_queue()
    assert str(HERE.parent / 'mathlib-etale-repro/run.py').encode() in cmdline(CHILD)
    assert str(STAGE.parent).encode() in cmdline(CHILD)
    sources = [BINARY, HERE/'suspended6-conversion.ml', HERE/'reviewed_typeops.ml',
               HERE/'reviewed_mod_checking.ml', HERE/'run.py', HERE/'recheck.ml']
    def hashes():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    before = hashes()
    signal.signal(signal.SIGTERM, abort)
    signal.signal(signal.SIGINT, abort)
    os.kill(QUEUE, signal.SIGSTOP)
    try:
        print('Queue held; current worker remains running', flush=True)
        deadline = time.monotonic() + 3900
        while not STAGE.exists():
            if time.monotonic() > deadline:
                raise RuntimeError('Current segment did not finish; releasing queue')
            time.sleep(5)
        record = json.loads(STAGE.read_text())
        if record['exit_code']:
            raise RuntimeError('Existing candidate segment failed; preserving its result')
        print('Segment passed; running isolated candidate', flush=True)
        env = dict(os.environ)
        env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_HEAD'] = 'MathlibTo5000000.Algebra.<ind>/4'
        result = subprocess.run([sys.executable, str(HERE/'run.py'), str(BINARY),
            str(HERE/'suspended-v6-full'), '--seconds', '1800', '--entries'], env=env, cwd=ROOT)
        assert hashes() == before, 'Diagnostic inputs changed'
        print('Diagnostic finished:', result.returncode, flush=True)
        return result.returncode
    finally:
        release()
        print('Validation queue released', flush=True)

if __name__ == '__main__':
    raise SystemExit(main())
