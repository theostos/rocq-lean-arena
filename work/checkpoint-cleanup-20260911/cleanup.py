#!/usr/bin/env python3
"""Audited removal of obsolete Mathlib replay binaries, never the import chain."""

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import subprocess


ROOT = Path('/home/theo/Documents/github/rocq-lean-typechecker')
AUDIT = ROOT / 'work/checkpoint-cleanup-20260911'
CHAIN = ROOT / 'work/mathlib-ndjson/checkpoints'
VALIDATION = ROOT / 'work/mathlib-basic-open-repro/validation-8gccux_c'
REPLAY_DIRS = [ROOT / 'work' / name for name in (
    'mathlib-basic-open-repro', 'mathlib-mul-fin-two-repro',
    'mathlib-proj-app-repro', 'mathlib-punit-ext-repro',
    'mathlib-punit-colimit-repro', 'mathlib-11m-investigation',
    'mathlib-timeout-investigation', 'mathlib-contdiff-repro',
    'mathlib-extdtree-repro', 'mathlib-original-dependency-cache',
    'structured-arrow-repro',
)]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_new(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def plain_file(path):
    if path.resolve() != path or not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError('Not a regular, non-symlink file: ' + str(path))


def idle():
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if process.joinpath('comm').read_text().strip() in ('rocqworker', 'rocqworker.exe'):
                raise RuntimeError('A Rocq worker is running: ' + process.name)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue


def protected():
    # Read manifests only: load_plan would rewrite checkpoint sources.
    paths = {CHAIN / 'plan.json', CHAIN / 'progress.json'}
    for seal in CHAIN.glob('*.seal'):
        for manifest in seal.glob('*.sha256'):
            paths.add(manifest)
            for line in manifest.read_text().splitlines():
                _, name = line.split('  ', 1)
                paths.add(Path(name))
    current = json.loads((VALIDATION / 'passed.json').read_text())
    paths.update(Path(name) for name in current['inputs'])
    # Keep the complete current validation, plus its staged external kernel suite.
    kernel = Path((VALIDATION / 'kernel.log').read_text().splitlines()[0])
    for directory in (VALIDATION, kernel):
        paths.update(path for path in directory.rglob('*') if path.is_file())
    # The most recent reload is still the one recorded by the progress marker.
    progress = json.loads((CHAIN / 'progress.json').read_text())
    paths.add(CHAIN / (progress['module'] + 'Reload.vo'))
    return paths


def candidates(keep):
    command = ['rg', '--files', '--hidden', '--no-ignore', '-0',
               '-g', '*.vo', '-g', '*.vo.gz']
    command.extend(str(path) for path in REPLAY_DIRS)
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE)
    found = {Path(name.decode()) for name in result.stdout.split(b'\0') if name}
    # These empty-import reload modules are not dependencies of any checkpoint.
    found.update(CHAIN / ('MathlibTo%dReload.vo' % (n * 1_000_000))
                 for n in range(1, 19))
    return sorted(path for path in found if path not in keep
                  and path.name not in ('Lean.vo', 'Lean.vo.gz'))


def allowed(path):
    if path.parent == CHAIN:
        match = re.fullmatch(r'MathlibTo(\d+)Reload\.vo', path.name)
        return bool(match and 1_000_000 <= int(match[1]) <= 18_000_000
                    and int(match[1]) % 1_000_000 == 0)
    return any(path.is_relative_to(directory) for directory in REPLAY_DIRS)


def source_for(path):
    raw = path.with_suffix('') if path.suffix == '.gz' else path
    return raw.with_suffix('.v')


def metadata(path):
    plain_file(path)
    info = path.stat()
    return {'path': str(path), 'sha256': digest(path), 'bytes': info.st_size,
            'allocated_bytes': info.st_blocks * 512,
            'device': info.st_dev, 'inode': info.st_ino, 'mtime_ns': info.st_mtime_ns}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('plan', 'apply'))
    args = parser.parse_args()
    with (ROOT / 'work/cslib-full-fresh/runs/cslib-unit-fix/launcher.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        idle()
        keep = protected()
        if args.mode == 'plan':
            targets, skipped = [], []
            for path in candidates(keep):
                plain_file(path)
                if not allowed(path):
                    raise RuntimeError('Outside cleanup scope: ' + str(path))
                source = source_for(path)
                if not source.is_file():
                    skipped.append({'path': str(path), 'reason': 'No adjacent rebuild source'})
                    continue
                item = metadata(path)
                item['source'] = str(source)
                item['source_sha256'] = digest(source)
                targets.append(item)
            preserved = sorted(path for path in keep if path.is_relative_to(CHAIN)
                               or path.is_relative_to(VALIDATION))
            report = {
                'created': datetime.now(timezone.utc).isoformat(),
                'before_free_bytes': shutil.disk_usage(ROOT).free,
                'reason': 'User requested maximum removal of unused checkpoints',
                'preserved_sha256': {str(path): digest(path) for path in preserved},
                'targets': targets, 'skipped': skipped,
                'allocated_bytes': sum(item['allocated_bytes'] for item in targets),
                'recovery': 'Binaries are permanently removed; sources, logs and hashes remain for rebuilding.',
            }
            write_new(AUDIT / 'plan.json', report)
            print(json.dumps({'files': len(targets), 'gib': report['allocated_bytes'] / 1024**3,
                              'skipped': skipped, 'plan': str(AUDIT / 'plan.json')}, indent=2))
            return
        if (AUDIT / 'removed.jsonl').exists() or (AUDIT / 'result.json').exists():
            raise RuntimeError('Cleanup already started; inspect the audit before retrying')
        report = json.loads((AUDIT / 'plan.json').read_text())
        for name, expected in report['preserved_sha256'].items():
            if digest(Path(name)) != expected:
                raise RuntimeError('Protected artifact changed: ' + name)
        # Validate the entire explicit, reviewed inventory before deleting anything.
        for item in report['targets']:
            path, source = Path(item['path']), Path(item['source'])
            if path in keep or not allowed(path) or source_for(path) != source:
                raise RuntimeError('Target now protected or outside scope: ' + str(path))
            actual = metadata(path)
            if any(actual[key] != item[key] for key in actual):
                raise RuntimeError('Target changed: ' + str(path))
            if digest(source) != item['source_sha256']:
                raise RuntimeError('Rebuild source changed: ' + str(source))
        idle()
        before = shutil.disk_usage(ROOT).free
        with (AUDIT / 'removed.jsonl').open('x', buffering=1) as journal:
            for item in report['targets']:
                path = Path(item['path'])
                plain_file(path)
                path.unlink()  # Single validated file only; never recursive.
                journal.write(json.dumps({'path': str(path), 'sha256': item['sha256']}) + '\n')
        for name, expected in report['preserved_sha256'].items():
            if digest(Path(name)) != expected:
                raise RuntimeError('Protected artifact changed after cleanup: ' + name)
        result = {'completed': datetime.now(timezone.utc).isoformat(),
                  'files_removed': len(report['targets']), 'before_free_bytes': before,
                  'after_free_bytes': shutil.disk_usage(ROOT).free,
                  'protected_artifacts_unchanged': len(report['preserved_sha256'])}
        write_new(AUDIT / 'result.json', result)
        print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
