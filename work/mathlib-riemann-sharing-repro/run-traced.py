#!/usr/bin/env python3
"""Guarded replay with a startup debugger and model-free stall snapshots."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import signal

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

GENERATION = ROOT / 'work/mathlib-alignment-5m-20260913-with-terminal'
TARGET = 2499931
TRACE = ROOT / 'scripts/mathlib_ndjson_trace.gdb'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--prefix', type=Path, action='append', default=[])
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--checkpoint-limit', type=int, default=10000000,
                        help='Verify and pin the complete checkpoint chain up to this line')
    parser.add_argument('--entries', action='store_true')
    parser.add_argument('--trace-call', type=int)
    args = parser.parse_args()
    if args.checkpoint_limit <= 0 or args.checkpoint_limit % 5000000:
        raise ValueError('Expected a positive five-million checkpoint boundary')
    if args.native and args.checkpoint_limit != 10000000:
        raise ValueError('Native slices do not use the full checkpoint chain')
    source = args.source.resolve(strict=True)
    directory = args.directory.resolve()
    if directory.parent != HERE or directory.exists():
        raise ValueError('Expected a new diagnostic directory')
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    importer = Path(profile['importer'])
    consumer = os.environ.get('ROCQ_ALIGNMENT_IMPORTER')
    if consumer:
        importer = Path(consumer).resolve(strict=True)
        if importer.parent != ROOT / 'work/kernel-alignment-pass' or not importer.name.startswith('importer.'):
            raise ValueError('Expected an isolated consumer importer')
    direct.checking.IMPORTER = importer
    inputs = {str(p): chunks.sha(p) for p in (source, chunks.WORKER, Path(__file__), plan_path, TRACE, Path('/usr/bin/gdb'))}
    if consumer:
        for path in (importer / 'src').iterdir():
            if path.suffix in ('.ml', '.mli', '.mlg', '.cmxs') or path.name.startswith('META'):
                inputs[str(path)] = chunks.sha(path)
    for path in dict.fromkeys(re.findall(r'Lean Import "([^"]+)"', source.read_text())):
        inputs[path] = chunks.sha(Path(path))
    with (chunks.OLD_RUN / 'launcher.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        chunks.check_entries(profile['inputs'])
        inputs.update(profile['inputs'])
        if not args.native:
            boundary = args.checkpoint_limit + 1
            predecessors = [c for c in plan['chunks'] if c['end'] <= boundary]
            if not predecessors or predecessors[-1]['end'] != boundary:
                raise ValueError('Expected the complete requested checkpoint chain')
            for chunk in predecessors:
                if chunks.verify_saved(plan_path.parent, chunk) is None:
                    raise ValueError('Missing sealed checkpoint: ' + chunk['module'])
                for suffix in ('.v', '.vo'):
                    path = plan_path.parent / (chunk['module'] + suffix)
                    inputs[str(path)] = chunks.sha(path)
            inputs[plan['export']] = plan['export_sha256']
        extra = []
        for prefix in args.prefix:
            prefix = prefix.resolve(strict=True)
            record = json.loads((prefix / 'result.json').read_text())
            artifact = prefix / (record['module'] + '.vo')
            if record['exit_code'] or chunks.sha(artifact) != record['vo_sha256']:
                raise ValueError('Unverified diagnostic ancestor')
            for path in (prefix / 'result.json', artifact, artifact.with_suffix('.v')):
                inputs[str(path)] = chunks.sha(path)
            extra.extend(['-Q', str(prefix), ''])
        chunks.check_entries(inputs)
        chunks.check_disk(HERE)
        directory.mkdir()
        target = directory / source.name
        shutil.copy2(source, target)
        env = direct.environment(16384)
        # Keep a detached validation scope bound to its verified owner service.
        # The guard rejects this value unless it names our enclosing cgroup.
        if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
            env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
        env.update(LEAN_IMPORT_DECLARE_TRACE_LINE=str(TARGET),
                   LEAN_IMPORT_EXCEPTION_BACKTRACE='1', LEAN_IMPORT_CHECKPOINT_STATS='1')
        if args.entries:
            env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
        if args.trace_call is not None:
            env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
        command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '3600s',
                   '/usr/bin/gdb', '--batch', '--return-child-result', '-x', str(TRACE), '--args',
                   str(chunks.WORKER), '--kind=compile', '-coqlib', env['COQLIB'],
                   '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
                   '-Q', str(GENERATION / 'foundation'), 'LeanImport', '-I', str(importer / 'src'),
                   *extra, '-Q', str(plan_path.parent), '', '-Q', str(directory), '', str(target)]
        chunks.save_json(directory / 'invocation.json', {'command': command, 'inputs': inputs})
        print(directory, flush=True)
        started = time.monotonic()
        with (directory / 'run.log').open('x') as log:
            process = subprocess.Popen(command, cwd=directory, env=env,
                                       stdout=log, stderr=subprocess.STDOUT)
            offset, pending, key = 0, '', None
            changed, sampled, samples = time.monotonic(), 0.0, 0
            while process.poll() is None:
                time.sleep(5)
                with (directory / 'run.log').open(errors='replace') as reader:
                    reader.seek(offset)
                    records = (pending + reader.read(1024 * 1024)).split('\n')
                    pending, offset = records.pop(), reader.tell()
                for line in records:
                    match = re.match(r'line (\d+): (.+)', line)
                    if match and match.groups() != key:
                        key = match.groups()
                        changed, sampled, samples = time.monotonic(), 0.0, 0
                now = time.monotonic()
                if now - changed < 60 or now - sampled < 60 or samples >= 3:
                    continue
                for proc in Path('/proc').iterdir():
                    if not proc.name.isdigit():
                        continue
                    try:
                        if proc.stat().st_uid != os.getuid():
                            continue
                        if not proc.joinpath('comm').read_text().strip().startswith('rocqworker'):
                            continue
                        if str(directory).encode() not in proc.joinpath('cmdline').read_bytes():
                            continue
                        status = dict(line.split(':', 1) for line in proc.joinpath('status').read_text().splitlines())
                        parent = Path('/proc') / status['PPid'].strip()
                        if parent.joinpath('comm').read_text().strip() != 'gdb':
                            continue
                        os.kill(int(proc.name), signal.SIGUSR1)
                        sampled, samples = now, samples + 1
                        break
                    except (FileNotFoundError, ProcessLookupError, KeyError):
                        continue
            result = subprocess.CompletedProcess(command, process.returncode)
        chunks.check_entries(inputs)
        record = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
                  'module': target.stem, 'worker_sha256': inputs[str(chunks.WORKER)]}
        if not result.returncode:
            record['vo_sha256'] = chunks.sha(target.with_suffix('.vo'))
        chunks.save_json(directory / 'result.json', record)
        print(json.dumps(record), flush=True)
        return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
