#!/usr/bin/env python3
"""Remove only completed temporary test executables created by this repair."""
from pathlib import Path
import os
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

# Exact directories observed in this repair's test invocations, not a wildcard
# over earlier experiments. Sources, compiled objects, logs and .vo files stay.
parents = [HERE.parent / 'kernel-alignment-pass' / name for name in (
    'closure-candidate.G11RLU6Y', 'quotation-test.eVahBCvo', 'strict-flags.PCJq05AU',
    'witness-candidate.5m1gT89g', 'witness-candidate.RbmrkphK',
    'witness-candidate.VpajoQRe', 'witness-candidate.jBMKpVeI')]
assert (HERE.parent / 'kernel-alignment-pass/final-gates-21/passed.json').is_file()
manifest = HERE / 'cleanup-test-executables.json'
assert not manifest.exists()
targets = []
for parent in parents:
    assert parent.resolve(strict=True) == parent
    for path in sorted(parent.iterdir()):
        if path.suffix != '.exe':
            continue
        assert path.is_file() and not path.is_symlink()
        assert any(parent.glob('*.cmx'))
        targets.append({'path': str(path), 'bytes': path.stat().st_size,
                        'sha256': chunks.sha(path)})
executing = set()
for process in Path('/proc').iterdir():
    if process.name.isdigit():
        try:
            if process.stat().st_uid == os.getuid():
                executing.add(str((process / 'exe').resolve(strict=True)))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
assert all(t['path'] not in executing for t in targets)
chunks.save_json(manifest, {'phase': 'validated', 'files': targets,
    'bytes': sum(t['bytes'] for t in targets), 'checkpoints_removed': 0,
    'recovery': 'Relink retained objects or rerun the retained test build scripts.'})
for target in targets:
    path = Path(target['path'])
    assert path.parent in parents and path.stat().st_size == target['bytes']
    assert chunks.sha(path) == target['sha256']
    path.unlink()
chunks.save_json(manifest, {'phase': 'complete', 'files': targets,
    'bytes': sum(t['bytes'] for t in targets), 'checkpoints_removed': 0,
    'recovery': 'Relink retained objects or rerun the retained test build scripts.'})
print(len(targets), 'regenerable test executables removed;',
      sum(t['bytes'] for t in targets), 'bytes freed; no checkpoints removed')
