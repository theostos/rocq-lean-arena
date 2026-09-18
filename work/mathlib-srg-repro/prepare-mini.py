#!/usr/bin/env python3
"""Build a small, proof-preserving constructor-context regression export."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LEAN = Path('/home/theo/.elan/toolchains/leanprover--lean4---v4.29.0/bin/lean')
EXPORTER = ROOT / '_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.29.0'
CONVERTER = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
BUILD = HERE / 'mini-build'
BUILD.mkdir(exist_ok=True)
env = dict(os.environ, LEAN_PATH=str(BUILD) + ':' + str(HERE))
commands = []
def run(args, cwd, output=None):
    command = ['timeout', '--kill-after=5s', '120', *map(str, args)]
    commands.append(command)
    subprocess.run(command, cwd=cwd, env=env, stdout=output, check=True)
run([LEAN, '-o', BUILD / 'Export.olean', 'Export.lean'], EXPORTER)
run([LEAN, '-o', BUILD / 'ConstructorScope.olean', 'ConstructorScope.lean'], HERE)
with (HERE / 'ConstructorScope.ndjson').open('x') as output:
    run([LEAN, '--run', 'Main.lean', 'ConstructorScope', '--', 'ParameterScope',
         'FieldScope', 'scopeSize_example'], EXPORTER, output)
env['ROCQLKA_NDJSON_STREAM'] = '1'
run(['/usr/bin/python3', CONVERTER, HERE / 'ConstructorScope.ndjson',
     HERE / 'ConstructorScope.lean-export'], HERE)
def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()
inputs = [Path(__file__), HERE / 'ConstructorScope.lean', LEAN,
          EXPORTER / 'Export.lean', EXPORTER / 'Main.lean', CONVERTER]
outputs = [HERE / 'ConstructorScope.ndjson', HERE / 'ConstructorScope.lean-export']
with (HERE / 'mini.json').open('x') as out:
    json.dump({'inputs': {str(p): sha(p) for p in inputs},
               'outputs': {str(p): sha(p) for p in outputs}, 'commands': commands}, out, indent=2)
