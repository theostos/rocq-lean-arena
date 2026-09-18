#!/usr/bin/env python3
"""Export original declarations using CSLib's actual Lean 4.27 toolchain."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
LEAN = Path('/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1/bin')
EXPORTER = ROOT / '_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export'
SOURCE = ROOT / '_deps/lean-kernel-arena/_build/tests/work/cslib/src'
CONVERTER = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
environment = {**os.environ, 'PATH': str(LEAN) + ':' + os.environ['PATH'], 'ROCQLKA_NDJSON_STREAM': '1'}
manifest = OUT / 'target-exports.json'
results = json.loads(manifest.read_text()) if manifest.exists() else []
for name, module, declarations in [
    ('DiscrTree427', 'Lean.Meta.DiscrTree', ['Lean.Meta.DiscrTree.Trie.casesOn', 'Lean.Meta.DiscrTree.casesOn']),
    ('FreeM427', 'Cslib.Foundations.Control.Monad.Free.Fold',
     ['Cslib.FreeM.bind_assoc', 'Cslib.FreeM.foldFreeM_unique']),
]:
    ndjson = OUT / (name + '.ndjson')
    target = OUT / (name + '.lean-export')
    recorded = next((entry for entry in results if entry['name'] == name), None)
    if recorded is not None:
        assert hashlib.file_digest(target.open('rb'), 'sha256').hexdigest() == recorded['sha256']
        continue
    assert not ndjson.exists() and not target.exists(), name
    command = [str(LEAN / 'lake'), 'env', str(EXPORTER), module, '--', *declarations]
    with ndjson.open('wb') as output:
        subprocess.run(command, cwd=SOURCE, env=environment, stdout=output, check=True, timeout=120)
    subprocess.run(['python3', str(CONVERTER), str(ndjson), str(target)],
                   cwd=ROOT, env=environment, check=True, timeout=60)
    result = {'name': name, 'command': command, 'module': module, 'declarations': declarations,
              'lines': sum(1 for _ in target.open()), 'bytes': target.stat().st_size,
              'sha256': hashlib.file_digest(target.open('rb'), 'sha256').hexdigest()}
    results.append(result)
    (OUT / 'target-exports.json').write_text(json.dumps(results, indent=2) + '\n')
    for variant in ('with', 'without'):
        test = ROOT / f'_worktrees/review/pr70-cslib-{variant}/tests/ablation_{name.lower()}.v'
        test.write_text('From LeanImport Require Import Lean.\n'
                        'Set Lean Error Mode "Fail".\n'
                        'Set Lean Line Timeout 30.\n'
                        f'Lean Import "{target}".\n')
    print(json.dumps(result), flush=True)
