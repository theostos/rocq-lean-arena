#!/usr/bin/env python3
"""Archive small historical review evidence, never binaries or active run output."""
import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[2]


def candidates():
    for parent, dirs, files in os.walk(ROOT / 'work'):
        dirs[:] = [d for d in dirs if not (
            d.startswith(('.', 'importer.', 'handoff-', 'pr78-'))
            or d in {'__pycache__', '_build', '_deps', '_worktrees', 'checkpoints', 'attempts', 'runs'}
            or 'alignment-5m-' in d)]
        for name in files:
            p = Path(parent) / name
            if not p.is_symlink() and p.is_file() and p.suffix in {'.json', '.md', '.log', '.sha256'}:
                yield p
    state = ROOT / 'work/handoff-20260918'
    for name in ('kernel-source.json', 'importer-source.json', 'arena-source.json'):
        yield state / name
    # These two checkpoints are completed; do not copy their active successor.
    completed = ROOT / 'work/mathlib-alignment-5m-20260913-with-terminal/attempts/20260918T082259901642Z'
    for module in ('MathlibTo55000000', 'MathlibTo55000000Reload'):
        for suffix in ('.run.log', '.guard.log'):
            yield completed / (module + suffix)


def pack(output):
    if output.exists() or output.with_suffix('.manifest.json').exists():
        raise RuntimeError('Evidence package already exists')
    inventory, excluded = {}, []
    with output.open('xb') as raw, gzip.GzipFile(fileobj=raw, mode='wb', mtime=0) as gz, \
            tarfile.open(fileobj=gz, mode='w|') as archive:
        for source in sorted(set(candidates())):
            name = str(source.relative_to(ROOT))
            if not source.is_file():
                excluded.append({'path': name, 'reason': 'missing'})
                continue
            before = source.stat()
            if before.st_size > 8 * 1024**2:
                excluded.append({'path': name, 'reason': 'larger than 8 MiB', 'size': before.st_size})
                continue
            data = source.read_bytes()
            after = source.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise RuntimeError('Evidence changed while reading: ' + name)
            inventory[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(data), 0o644
            archive.addfile(info, io.BytesIO(data))
        manifest = {'format': 'mathlib-small-evidence-v1', 'files': inventory,
                    'excluded': excluded, 'not_included': ['compiled artifacts', 'large exports',
                    'active checkpoint stages', 'active run logs', 'chat/session histories'],
                    'scope': 'Historical evidence, not a runnable checkpoint or a fresh validation'}
        data = (json.dumps(manifest, indent=2) + '\n').encode()
        info = tarfile.TarInfo('EVIDENCE-MANIFEST.json')
        info.size, info.mode = len(data), 0o644
        archive.addfile(info, io.BytesIO(data))
    with output.with_suffix('.manifest.json').open('x') as f:
        json.dump(manifest, f, indent=2)
        f.write('\n')
    print(json.dumps({'files': len(inventory), 'excluded': len(excluded),
                      'archive_bytes': output.stat().st_size,
                      'archive_sha256': file_sha(output)}), flush=True)


def file_sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def verify(output):
    with tarfile.open(output, 'r:gz') as archive:
        manifest = json.load(archive.extractfile('EVIDENCE-MANIFEST.json'))
        expected = manifest['files']
        seen = set()
        for info in archive:
            p = Path(info.name)
            if not info.isfile() or p.is_absolute() or '..' in p.parts or info.name in seen:
                raise RuntimeError('Invalid archive member: ' + info.name)
            seen.add(info.name)
            if info.name == 'EVIDENCE-MANIFEST.json':
                continue
            data = archive.extractfile(info).read()
            assert expected[info.name] == {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
        assert seen == set(expected) | {'EVIDENCE-MANIFEST.json'}
    print(json.dumps({'verified_files': len(expected), 'archive_sha256': file_sha(output)}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['pack', 'verify'])
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    (pack if args.action == 'pack' else verify)(args.archive.resolve())
