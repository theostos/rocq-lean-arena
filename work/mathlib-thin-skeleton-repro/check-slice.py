#!/usr/bin/env python3
"""Independent replay recheck, with an explicit compatibility-profile choice."""
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

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
parser.add_argument('--compatibility', action='store_true')
args = parser.parse_args()
directory = args.directory.resolve(strict=True)
assert directory.parent == HERE
label = 'compatibility-independent' if args.compatibility else 'strict-independent'
record = json.loads((directory / 'result.json').read_text())
artifact = directory / 'Slice.vo'
assert record['exit_code'] == 0 and chunks.sha(artifact) == record['vo_sha256']
foundation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal/foundation'
checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
inputs = {str(p): chunks.sha(p) for p in
    (artifact, checker, foundation / 'Lean.vo', directory / 'result.json', Path(__file__))}
inputs.update({str(p): chunks.sha(p) for p in direct.checking.STDLIB.rglob('*.vo')})
command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '600s',
    str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
    '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(foundation), 'LeanImport',
    '-Q', str(directory), '',
    *([] if args.compatibility else ['-strict', '-allow-uip']), '-o', 'Slice']
started = time.monotonic()
with (directory / (label + '.log')).open('x') as output:
    result = subprocess.run(command, env=direct.environment(3072),
        stdout=output, stderr=subprocess.STDOUT)
chunks.check_entries(inputs)
chunks.save_json(directory / (label + '.json'), {
    'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
    'command': command, 'inputs': inputs, 'admitted_dependencies': False,
    'strict': not args.compatibility})
raise SystemExit(result.returncode)
