#!/usr/bin/env python3
"""Check a target against the verified original prefix without resaving it.

Diagnostic evidence only. A successful debugger stop is not a checked .vo or
a production checkpoint. Final acceptance uses the uninterrupted saved replay.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('directory', type=Path)
parser.add_argument('--trace-call', type=int)
parser.add_argument('--uninterrupted', action='store_true')
args = parser.parse_args()
source, directory = args.source.resolve(strict=True), args.directory.resolve()
assert source.parent == HERE and directory.parent == HERE and not directory.exists()
if args.uninterrupted:
    assert source.name == 'MathlibTo35000000.v'
    assert 'Require Import MathlibTo30000000.' in source.read_text()
else:
    assert 'Require Import CharOriginalPrefix.' in source.read_text()
prefix = HERE / 'original-prefix'
record_path, invocation_path = prefix / 'result.json', prefix / 'invocation.json'
record = json.loads(record_path.read_text())
assert record['exit_code'] == 0 and record['module'] == 'CharOriginalPrefix'
ancestor = json.loads(invocation_path.read_text())
inputs = dict(ancestor['inputs'])
assert inputs.pop(str(chunks.WORKER)) == record['worker_sha256']
inputs[str(HERE / 'baseline-worker.exe')] = record['worker_sha256']
inputs[str(prefix / 'CharOriginalPrefix.vo')] = record['vo_sha256']
for path in (record_path, invocation_path, source, Path(__file__),
             HERE / 'check-only.gdb', chunks.WORKER):
    inputs[str(path)] = chunks.sha(path)
command = list(ancestor['command'])
command[command.index('3600s')] = '900s'
command[command.index('-x') + 1] = str(HERE / 'check-only.gdb')
# The last -Q names the output directory. Add the verified ancestor separately.
assert command[-4:] == ['-Q', str(prefix), '', str(prefix / 'CharOriginalPrefix.v')]
command[-4:] = ['-Q', str(prefix), '', '-Q', str(directory), '', str(directory / source.name)]
consumer = Path(os.environ['ROCQ_ALIGNMENT_IMPORTER']).resolve(strict=True)
assert command[command.index('-I') + 1] == str(consumer / 'src')
direct.checking.IMPORTER = consumer
environment = direct.environment(16384)
environment.update(LEAN_IMPORT_DECLARE_TRACE_LINE='30778865',
    LEAN_IMPORT_EXCEPTION_BACKTRACE='1', LEAN_IMPORT_CHECKPOINT_STATS='1',
    ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES='1')
if args.trace_call is not None:
    environment['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
with (chunks.OLD_RUN / 'launcher.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    chunks.check_entries(inputs)
    directory.mkdir()
    shutil.copy2(source, directory / source.name)
    chunks.save_json(directory / 'invocation.json', {'command': command, 'inputs': inputs})
    started = time.monotonic()
    with (directory / 'run.log').open('x') as output:
        result = subprocess.run(command, cwd=directory, env=environment,
                                stdout=output, stderr=subprocess.STDOUT)
    chunks.check_entries(inputs)
    marker = '[diagnostic completed checking; stopped before checkpoint pack]'
    completed = result.returncode == 0 and marker in (directory / 'run.log').read_text()
    report = {'exit_code': 0 if completed else (result.returncode or 1),
        'process_exit_code': result.returncode, 'completed_checking': completed,
        'wall_seconds': time.monotonic() - started, 'worker_sha256': inputs[str(chunks.WORKER)],
        'artifact_produced': False, 'scope': 'Diagnostic, stopped before saving importer state'}
    chunks.save_json(directory / 'result.json', report)
    print(json.dumps(report), flush=True)
raise SystemExit(report['exit_code'])
