#!/usr/bin/env python3
"""Run the DAG-aware diagnostic serially, then thaw the existing validation.

The validation service is held between stages, with no compiler in its cgroup.
The separate lambda diagnostic keeps running. Source and binary hashes are
pinned for this experiment; full acceptance still requires fresh qualification.
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
UNIT = 'rocq-mathlib-integral-cache-v8.service'
BINARY = HERE/'checker.bz3hhScv/recheck.exe'
STATE = HERE/'syntax-dag-status.json'
sys.path.insert(0, str(HERE.parent/'mathlib-char-succ-repro'))
from resource_queue import wait_for_memory

def status(phase, **details):
    value = {'phase': phase, 'updated_unix': time.time(), **details}
    tmp = STATE.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, indent=2)+'\n')
    tmp.replace(STATE)
    print(json.dumps(value), flush=True)

def thaw():
    subprocess.run(['systemctl','--user','thaw',UNIT], check=False)

def abort(signum, _frame):
    raise SystemExit(128+signum)

def main():
    signal.signal(signal.SIGTERM, abort)
    signal.signal(signal.SIGINT, abort)
    sources = [BINARY, HERE/'suspended7-conversion.ml', HERE/'reviewed_typeops.ml',
               HERE/'reviewed_mod_checking.ml', HERE/'run.py', HERE/'recheck.ml']
    def hashes():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    before = hashes()
    try:
        status('waiting_for_lambda_diagnostic', inputs=before)
        previous = HERE/'suspended-v6-full/result.json'
        deadline = time.monotonic()+2100
        while not previous.exists():
            if time.monotonic()>deadline:
                raise RuntimeError('Previous diagnostic did not finish')
            time.sleep(5)
        record = json.loads(previous.read_text())
        if record['exit_code'] or not record['checked_target']:
            raise RuntimeError('Previous complete proof diagnostic failed')
        wait_for_memory(12288, lambda **m: status('waiting_for_memory', **m))
        assert hashes()==before, 'Candidate inputs changed before launch'
        status('running_full_diagnostic', memory_mib=12288, reserve_mib=3072)
        env = dict(os.environ)
        env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_HEAD'] = 'MathlibTo5000000.Algebra.<ind>/4'
        result = subprocess.run([sys.executable,str(HERE/'run.py'),str(BINARY),
            str(HERE/'suspended-v7-full'),'--seconds','1800','--entries'], env=env, cwd=ROOT)
        assert hashes()==before, 'Candidate inputs changed during checking'
        status('passed' if result.returncode==0 else 'failed', exit_code=result.returncode,
               production_evidence=False)
        return result.returncode
    except Exception as error:
        status('failed', reason=str(error), production_evidence=False)
        raise
    finally:
        thaw()
        print('Existing validation service thawed', flush=True)

if __name__ == '__main__':
    raise SystemExit(main())
