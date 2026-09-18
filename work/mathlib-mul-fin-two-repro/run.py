#!/usr/bin/env python3
"""Isolated guarded replays for Matrix.mul_fin_two, from the sealed 17M chain."""
import argparse
import fcntl
from functools import lru_cache
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

CHECKPOINTS = ROOT / 'work/mathlib-ndjson/checkpoints'
TARGET = 17631905
CHECKPOINT_END = 17000001


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--prefix', type=Path)
    parser.add_argument('--entries', action='store_true')
    parser.add_argument('--trace-call', type=int)
    parser.add_argument('--dump', action='store_true')
    parser.add_argument('--gdb', type=Path)
    parser.add_argument('--wait', action='store_true')
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--worker', type=Path, default=chunks.WORKER)
    parser.add_argument('--directory', type=Path)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    worker = args.worker.resolve(strict=True)
    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | (0 if args.wait else fcntl.LOCK_NB))
        original_sha = chunks.sha
        if args.native:
            if 'Require' in source.read_text() or args.prefix:
                raise RuntimeError('Native mode must not import checkpoints')
            chunks.check_disk(HERE)
        else:
            chunks.sha = lru_cache(maxsize=None)(original_sha)
            plan = json.loads((CHECKPOINTS / 'plan.json').read_text())
            chunks.check_entries(chunks.generation_toolchain(plan)['inputs'])
            if chunks.sha(plan['export']) != plan['export_sha256']:
                raise RuntimeError('Export changed')
            for chunk in plan['chunks']:
                if chunk['end'] <= CHECKPOINT_END:
                    if chunks.verify_saved(CHECKPOINTS, chunk) is None:
                        raise RuntimeError('Missing checkpoint: ' + chunk['module'])
            chunks.check_disk(HERE, CHECKPOINTS / 'MathlibTo17000000.vo')
        if args.directory:
            stage = args.directory.resolve()
            stage.mkdir(parents=True, exist_ok=False)
        else:
            stage = Path(tempfile.mkdtemp(prefix=source.stem + '-', dir=HERE))
        shutil.copy2(source, stage / source.name)
        extra = []
        if args.prefix:
            prefix = args.prefix.resolve(strict=True)
            result = json.loads((prefix / 'result.json').read_text())
            invocation = json.loads((prefix / 'invocation.json').read_text())
            parent_source = Path(invocation['command'][-1])
            if parent_source.parent != prefix:
                raise RuntimeError('Unexpected parent artifact path')
            if result['exit_code'] != 0 or original_sha(parent_source.with_suffix('.vo')) != result['vo_sha256']:
                raise RuntimeError('Prefix is not a verified successful artifact')
            extra = ['-Q', str(prefix), '']
        env = direct.environment(16384)
        env.update(LEAN_IMPORT_DECLARE_TRACE_LINE=str(TARGET),
                   LEAN_IMPORT_EXCEPTION_BACKTRACE='1')
        if args.entries:
            env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
        if args.trace_call is not None:
            env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
        if args.dump:
            env['LEAN_IMPORT_DUMP_CURRENT_DEF'] = str(TARGET)
        debugger = ['gdb', '-q', '-nx', '--batch', '--return-child-result',
                    '-x', str(args.gdb.resolve(strict=True)), '--args'] if args.gdb else []
        command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '2400s',
                   *debugger, str(worker), '--kind=compile', '-coqlib', env['COQLIB'],
                   '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
                   '-Q', str(CHECKPOINTS), '',
                   '-Q', str(ROOT / 'work/mathlib-ndjson/foundation'), 'LeanImport',
                   '-I', str(direct.checking.IMPORTER / 'src'), *extra,
                   '-Q', str(stage), '', str(stage / source.name)]
        worker_sha = original_sha(worker)
        chunks.save_json(stage / 'invocation.json', {
            'command': command, 'source': source.read_text(), 'worker_sha256': worker_sha,
            'prefix': str(args.prefix) if args.prefix else None,
            'options': {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        })
        print(stage, flush=True)
        started = time.monotonic()
        with (stage / 'run.log').open('x') as log:
            result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
        data = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
                'worker_sha256': worker_sha}
        if original_sha(worker) != worker_sha:
            raise RuntimeError('Worker changed during diagnostic')
        if result.returncode == 0:
            data['vo_sha256'] = original_sha((stage / source.name).with_suffix('.vo'))
        chunks.save_json(stage / 'result.json', data)
        print(json.dumps(data), flush=True)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
