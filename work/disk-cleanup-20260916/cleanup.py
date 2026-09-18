#!/usr/bin/env python3
"""Remove only audited, inactive temporary OCaml test build outputs.

No checkpoint, importer, source, log, receipt, or directory is removed.
Run audit first; apply revalidates the explicit per-file inventory.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / 'work/kernel-alignment-pass'
GENERATION = ROOT / 'work/mathlib-alignment-5m-20260913-with-terminal'
PREFIX = re.compile(r'(witness-candidate|closure-candidate|quotation-test|typeops-cache|checker-typing)\.[A-Za-z0-9]{8}')
SUFFIXES = {'.exe', '.o', '.cmx', '.cmi', '.cmo', '.cma', '.cmxa', '.cmxs', '.a'}
MANIFEST = HERE / 'inventory.json'

# Reuse the previously reviewed read-only /proc scanner. It protects open and
# mapped paths/inodes and command-line directories, and refuses unknown jobs
# whose file references cannot be inspected. Its old cleanup main is not run.
OLD = ROOT / 'work/disk-audit-20260913'
sys.path.insert(0, str(OLD))
spec = importlib.util.spec_from_file_location('prior_cleanup', OLD / 'cleanup.py')
prior = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prior)


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def protected_paths():
    protected = set()

    def collect(value):
        if isinstance(value, dict):
            for key, item in value.items():
                collect(key)
                collect(item)
        elif isinstance(value, list):
            for item in value:
                collect(item)
        elif isinstance(value, str) and value.startswith(str(ROOT) + '/'):
            protected.add(value)

    for path in (
        GENERATION / 'toolchain.json', GENERATION / 'checkpoints/plan.json',
        ROOT / 'work/mathlib-etale-repro/consumer-certificate-etale-v9.json',
        ROOT / 'work/mathlib-etale-repro/resume-approval-etale-v9.json',
        ROOT / 'work/mathlib-etale-release-20260916-v9/validation-receipt.json',
    ):
        collect(json.loads(path.read_text()))
        protected.add(str(path))
    for path in (GENERATION / 'checkpoints').glob('*.seal/inputs.sha256'):
        for line in path.read_text().splitlines():
            if len(line) > 66:
                protected.add(line[66:])
    tracked = subprocess.check_output(
        ['git', '--no-optional-locks', '-C', str(ROOT), 'ls-files', '-z', '--', 'work'])
    protected.update(str(ROOT / os.fsdecode(name)) for name in tracked.split(b'\0') if name)
    return protected


def inspect(path):
    if (not path.is_absolute() or path.parent.parent != BUILD
            or not PREFIX.fullmatch(path.parent.name) or path.suffix not in SUFFIXES
            or path.resolve(strict=True) != path or (path.parent / '.git').exists()):
        raise ValueError('Outside explicit temporary build scope: ' + str(path))
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_uid != os.getuid():
        raise ValueError('Not a private regular build output: ' + str(path))
    return {'path': str(path), 'device': info.st_dev, 'inode': info.st_ino,
            'size': info.st_size, 'allocated': info.st_blocks * 512,
            'mtime_ns': info.st_mtime_ns, 'ctime_ns': info.st_ctime_ns}


def protections():
    paths, inodes, directories, evidence = prior.processes()
    paths = {str(ROOT / path) for path in paths} | protected_paths()
    directories = {str(ROOT / path) for path in directories}
    # Also avoid scratch directories used as a live process's working directory.
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cwd = (proc / 'cwd').resolve(strict=True)
            if cwd.is_relative_to(BUILD) and cwd != BUILD:
                directories.add(str(cwd) + '/')
        except (OSError, RuntimeError):
            continue
    return paths, inodes, tuple(directories), evidence


def blocked(item, protection):
    paths, inodes, directories, _ = protection
    return (item['path'] in paths or item['path'].startswith(directories)
            or (item['device'], item['inode']) in inodes)


def main(mode):
    if (HERE / 'removed.jsonl').exists():
        raise ValueError('Cleanup already applied or interrupted; inspect its journal')
    protection = protections()
    if mode == 'audit':
        selected, skipped = [], []
        for directory in sorted(BUILD.iterdir()):
            if not PREFIX.fullmatch(directory.name) or directory.is_symlink() or not directory.is_dir():
                continue
            for path in sorted(directory.iterdir()):
                if path.suffix not in SUFFIXES or path.is_symlink() or not path.is_file():
                    continue
                item = inspect(path)
                (skipped if blocked(item, protection) else selected).append(item)
        report = {'format': 'temporary-ocaml-cleanup-v1', 'files': selected,
                  'skipped_protected': skipped, 'process_evidence': protection[3],
                  'free_bytes_before': shutil.disk_usage(ROOT).free,
                  'allocated_bytes': sum(item['allocated'] for item in selected)}
        save(MANIFEST, report)
        print(json.dumps({'files': len(selected), 'GiB': report['allocated_bytes'] / 1024**3,
                          'protected_files_skipped': len(skipped), 'manifest': str(MANIFEST)}))
        return
    report = json.loads(MANIFEST.read_text())
    if report['format'] != 'temporary-ocaml-cleanup-v1':
        raise ValueError('Unexpected manifest')
    files = report['files']
    if len({item['path'] for item in files}) != len(files):
        raise ValueError('Duplicate cleanup paths')
    for item in files:
        if inspect(Path(item['path'])) != item or blocked(item, protection):
            raise ValueError('Changed or newly protected file: ' + item['path'])
    removed, allocated, last_scan = 0, 0, time.monotonic()
    with (HERE / 'removed.jsonl').open('x', buffering=1) as journal:
        for item in files:
            if time.monotonic() - last_scan > 10:
                protection, last_scan = protections(), time.monotonic()
            path = Path(item['path'])
            if inspect(path) != item or blocked(item, protection):
                raise ValueError('Changed or newly protected file during cleanup: ' + str(path))
            path.unlink()  # Individual audited regular file; never recursive.
            journal.write(json.dumps(item) + '\n')
            removed += 1
            allocated += item['allocated']
    result = {'removed_files': removed, 'allocated_bytes_reclaimed': allocated,
              'free_bytes_after': shutil.disk_usage(ROOT).free,
              'recovery': 'Rebuild test outputs from preserved sources; no trash copy.',
              'checkpoints_deleted': 0, 'importers_deleted': 0,
              'sources_logs_and_validation_records_preserved': True}
    save(HERE / 'result.json', result)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('audit', 'apply'))
    main(parser.parse_args().mode)
