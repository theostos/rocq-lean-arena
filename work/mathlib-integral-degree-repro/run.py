#!/usr/bin/env python3
"""Profile one stored proof; reused libraries are NOT fresh validation evidence."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

parser = argparse.ArgumentParser()
parser.add_argument('binary', type=Path)
parser.add_argument('directory', type=Path)
parser.add_argument('--seconds', type=int, default=240)
parser.add_argument('--entries', action='store_true')
args = parser.parse_args()
binary, directory = args.binary.resolve(strict=True), args.directory.resolve()
assert binary.parent.parent == HERE and directory.parent == HERE and not directory.exists()
generation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
original = HERE.parent / 'mathlib-etale-repro/original-etale-v7'
record = json.loads((original / 'result.json').read_text())
assert record['exit_code'] == 0 and record['module'] == 'MathlibTo35000000'
inputs = dict(json.loads((original / 'invocation.json').read_text())['inputs'])
inputs.pop(str(chunks.WORKER))
for path in (binary, original / 'MathlibTo35000000.vo', original / 'result.json',
             Path(__file__), HERE / 'sample.gdb', HERE / 'recheck.ml', HERE / 'build.sh'):
    inputs[str(path)] = chunks.sha(path)
assert inputs[str(original / 'MathlibTo35000000.vo')] == record['vo_sha256']
chunks.check_entries(inputs)
directory.mkdir()
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', str(args.seconds)+'s',
    'gdb', '--batch', '--return-child-result', '-x', str(HERE / 'sample.gdb'), '--args', str(binary),
    '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(generation / 'foundation'), 'LeanImport',
    '-Q', str(generation / 'checkpoints'), '', '-Q', str(original), '']
env = direct.environment(12288)
if args.entries:
    env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
env['ROCQ_DIAGNOSTIC_TYPEOPS_CACHE'] = '1'
chunks.save_json(directory / 'invocation.json', {'inputs': inputs, 'command': command,
    'scope': 'Only the named stored proof is rechecked; all loaded libraries are reused'})
started = time.monotonic()
with (directory / 'run.log').open('x') as output:
    result = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
complete = result.returncode == 0 and '[target checked]' in (directory / 'run.log').read_text()
chunks.save_json(directory / 'result.json', {'exit_code': result.returncode,
    'checked_target': complete, 'wall_seconds': time.monotonic()-started,
    'production_evidence': False, 'memory_mib': 12288})
raise SystemExit(result.returncode)
