#!/usr/bin/env python3
"""Sequential, one-factor tests after a checked pre-target prefix is ready."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', type=Path)
    args = parser.parse_args()
    prefix = args.prefix.resolve()
    print('Waiting for the checked pre-target prefix.', flush=True)
    while not (prefix / 'result.json').exists():
        time.sleep(5)
    if json.loads((prefix / 'result.json').read_text())['exit_code'] != 0:
        raise RuntimeError('Prefix preparation failed; no tests launched')
    # The prefix launcher writes its result immediately before releasing the lock.
    import fcntl
    root = HERE.parents[1]
    with (root / 'work/cslib-full-fresh/runs/cslib-unit-fix/launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
    results = []
    for strategy in ('default', 'projection-first', 'no-dependency-first', 'no-direct-arguments'):
        command = [sys.executable, str(HERE / 'focus.py'), '--prefix', str(prefix),
                   '--strategy', strategy, '--line-timeout', '60']
        print('Testing:', strategy, flush=True)
        result = subprocess.run(command, capture_output=True, text=True)
        paths = [Path(line) for line in result.stdout.splitlines() if line.startswith(str(HERE / 'focus-'))]
        stage = paths[0] if len(paths) == 1 else None
        entry = {'strategy': strategy, 'exit_code': result.returncode,
                 'stage': str(stage) if stage else None, 'stderr': result.stderr}
        if stage and (stage / 'run.log').exists():
            log = (stage / 'run.log').read_text()
            calls = re.findall(r'^\[conversion entry\] (\d+).*', log, re.M)
            entry['last_call'] = int(calls[-1]) if calls else None
            entry['timeout'] = 'Lean import line timed out.' in log
            entry['target_checked'] = '[declare done] Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq instance 0 ' in log
        results.append(entry)
        (prefix / 'comparisons.json').write_text(json.dumps(results, indent=2) + '\n')
        print(json.dumps(entry), flush=True)
        if not stage:
            raise RuntimeError('Test did not launch; see captured error')
    baseline = results[0]
    if baseline.get('timeout') and baseline.get('last_call'):
        command = [sys.executable, str(HERE / 'focus.py'), '--prefix', str(prefix),
                   '--line-timeout', '30', '--trace-call', str(baseline['last_call'])]
        print('Tracing the baseline conversion:', baseline['last_call'], flush=True)
        result = subprocess.run(command, check=False)
        print('Trace exit:', result.returncode, flush=True)


if __name__ == '__main__':
    main()
