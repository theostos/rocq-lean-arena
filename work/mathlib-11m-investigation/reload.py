#!/usr/bin/env python3
"""Fresh-process reload of a successful diagnostic Mathlib checkpoint."""
import argparse
import fcntl
from functools import lru_cache
import json
from pathlib import Path
import subprocess
import sys
import time

from reproduce import ROOT, CHECKPOINTS, chunks, direct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', type=Path)
    parser.add_argument('--worker', type=Path)
    parser.add_argument('--wait', action='store_true')
    args = parser.parse_args()
    stage = args.stage.resolve(strict=True)
    print('Reload:', stage, flush=True)
    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | (0 if args.wait else fcntl.LOCK_NB))
        chunks.sha = lru_cache(maxsize=None)(chunks.sha)
        metadata = json.loads((stage / 'invocation.json').read_text())
        result = json.loads((stage / 'result.json').read_text())
        source = Path(metadata['command'][-1])
        if result['exit_code'] != 0 or chunks.sha(source.with_suffix('.vo')) != result['vo_sha256']:
            raise RuntimeError('Not a successful, unchanged checkpoint')
        # Runner sources may gain diagnostics; all proof/toolchain inputs stay pinned.
        for filename, digest in metadata['inputs'].items():
            if filename != str(Path(__file__).with_name('reproduce.py')):
                if chunks.sha(filename) != digest:
                    raise RuntimeError('Input changed: ' + filename)
        plan = json.loads((CHECKPOINTS / 'plan.json').read_text())
        end = int(metadata['source'].splitlines()[-1].rstrip('.').split()[-1])
        reload_source = stage / 'Reload.v'
        chunks.immutable_text(reload_source, chunks.SETTINGS + f'Require Import {source.stem}.\n'
                              + f'Lean Import "{plan["export"]}" {end} {end}.\n')
        env = direct.environment(16384)
        env['LEAN_IMPORT_CHECKPOINT_STATS'] = '1'
        command = [*metadata['command'][:-1], str(reload_source)]
        worker = args.worker.resolve(strict=True) if args.worker else Path(metadata['worker'])
        command[command.index(metadata['worker'])] = str(worker)
        started = time.monotonic()
        with (stage / 'Reload.run.log').open('x') as log:
            code = subprocess.run(command, env=env, cwd=stage, stdout=log, stderr=subprocess.STDOUT).returncode
        data = {'exit_code': code, 'wall_seconds': time.monotonic() - started,
                'command': command, 'worker_sha256': chunks.sha(worker)}
        if code == 0:
            data['vo_sha256'] = chunks.sha(reload_source.with_suffix('.vo'))
        chunks.save_json(stage / 'Reload.result.json', data)
        print(json.dumps(data), flush=True)
        return code


if __name__ == '__main__':
    raise SystemExit(main())
