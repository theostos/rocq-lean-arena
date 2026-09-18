#!/usr/bin/env python3
"""Run one small kernel probe with existing diagnostic strategy switches."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts'))
import run_cslib_ndjson as direct
import run_chunked_import as chunks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--projection-first', action='store_true')
    parser.add_argument('--rigid-left-first', action='store_true')
    parser.add_argument('--source', type=Path, default=HERE / 'ProjectionCongruence.v')
    parser.add_argument('--worker', type=Path, default=chunks.WORKER)
    args = parser.parse_args()
    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        stage = Path(tempfile.mkdtemp(prefix='probe-', dir=HERE))
        source = stage / args.source.name
        shutil.copy2(args.source.resolve(), source)
        env = direct.environment(2048)
        if args.projection_first:
            env['ROCQ_DIAGNOSTIC_PROJECTION_FIRST'] = '1'
        if args.rigid_left_first:
            env['ROCQ_DIAGNOSTIC_RIGID_LEFT_FIRST'] = '1'
        if os.environ.get('ROCQ_MEMORY_OWNER_SERVICE'):
            env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
        command = ['bash', str(direct.checking.GUARD), 'timeout', '30s', str(args.worker.resolve()),
                   '--kind=compile', '-coqlib', env['COQLIB'], '-q', '-bytecode-compiler', 'no',
                   '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(stage), '', str(source)]
        print(stage, flush=True)
        with (stage / 'run.log').open('x') as log:
            result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        (stage / 'result.json').write_text(json.dumps({'command': command, 'projection_first': args.projection_first,
            'rigid_left_first': args.rigid_left_first,
            'worker_sha256': chunks.sha(args.worker), 'exit_code': result.returncode}) + '\n')
        print((stage / 'run.log').read_text()[-3000:], flush=True)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
