#!/usr/bin/env python3
"""Collect a bounded target trace, then run sequential focused probes."""
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
STAGE = (HERE / 'latest').resolve()
TARGET = 'Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq'


def main():
    print('Waiting for 120 CPU seconds and at least three native target samples; no model monitoring.', flush=True)
    start = cpu = pid = debugger = None
    samples = 0
    with (STAGE / 'run.log').open() as log:
        while not (STAGE / 'result.json').exists():
            line = log.readline()
            if not line:
                time.sleep(2)
                continue
            match = re.match(r'\[timeout worker\] pid=(\d+) debugger=(\d+)', line)
            if match:
                pid, debugger = map(int, match.groups())
            if line.startswith('[declare start] ' + TARGET + ' instance 0 '):
                start = float(re.search(r'cpu=([\d.]+)', line)[1])
                print('Target reached.', flush=True)
            if line.startswith('[declare done] ' + TARGET + ' instance 0 '):
                start = None
            if line.startswith('[dependency profile]'):
                cpu = float(re.search(r'cpu=([\d.]+)', line)[1])
            if start is not None and line.startswith('[timeout stack end]'):
                samples += 1
            if start is None or cpu is None or cpu - start < 120 or samples < 3:
                continue
            status = dict(line.split(':', 1) for line in Path(f'/proc/{pid}/status').read_text().splitlines())
            command = Path(f'/proc/{pid}/cmdline').read_bytes()
            if int(status['TracerPid']) != debugger or str(STAGE).encode() not in command:
                raise RuntimeError('Diagnostic worker identity changed; no signal sent')
            marker = {'reason': 'Intentional diagnostic cut, not expiry of the configured 1800-second limit',
                      'signal': 'SIGALRM', 'target': TARGET, 'target_cpu_seconds': cpu - start,
                      'samples': samples, 'worker': pid, 'wall': time.time()}
            (STAGE / 'diagnostic-cut.json').write_text(json.dumps(marker, indent=2) + '\n')
            os.kill(pid, signal.SIGALRM)
            print('Target trace collected; requested controlled timeout. Original 1800-second failure remains the baseline.', flush=True)
            break
    while not (STAGE / 'result.json').exists():
        time.sleep(2)
    # The report is written just before the original launcher releases its lock.
    import fcntl
    root = HERE.parents[1]
    with (root / 'work/cslib-full-fresh/runs/cslib-unit-fix/launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
    print('Diagnostic result:', (STAGE / 'result.json').read_text().strip(), flush=True)
    for flags in ([], ['--projection-first']):
        result = subprocess.run([sys.executable, str(HERE / 'probe.py'), *flags], check=False)
        print('Small probe', flags or ['default'], 'exit', result.returncode, flush=True)
    result = subprocess.run([sys.executable, str(HERE / 'focus.py'), '--lazy-prefix'], check=False)
    print('Dependency-focused baseline exit:', result.returncode, flush=True)


if __name__ == '__main__':
    main()
