#!/usr/bin/env python3
"""Install the pinned source layout only. Never build or start an import.

Existing directories must already have the exact pinned source; never reset,
clean, pull over modifications, or replace an existing unrelated checkout.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def git(path, *args):
    return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    record = json.loads((ROOT / 'docs/handoff-20260918.json').read_text())
    for name, spec in record['components'].items():
        target = ROOT / spec['directory']
        if not target.exists():
            if args.check:
                raise RuntimeError('Missing source: ' + str(target))
            target.parent.mkdir(parents=True, exist_ok=True)
            # Skip LFS fixture downloads; source/build files are ordinary Git blobs.
            env = dict(os.environ, GIT_LFS_SKIP_SMUDGE='1')
            command = ['git', 'clone', '--filter=blob:none', '--no-checkout']
            if name in ('kernel', 'importer'):
                command += ['--single-branch', '--branch', record['branch']]
            command += [spec['repository'], str(target)]
            subprocess.run(command, env=env, check=True)
            subprocess.run(['git', '-C', str(target), 'checkout', '--detach', spec['commit']],
                           env=env, check=True)
        if git(target, 'rev-parse', 'HEAD') != spec['commit']:
            raise RuntimeError('Different existing checkout: ' + str(target))
        expected_changed = {'lean-toolchain'} if name == 'exporter' else set()
        changed = set(filter(None, git(target, 'diff', '--name-only', 'HEAD').splitlines()))
        if changed - expected_changed:
            raise RuntimeError('Modified existing source: ' + str(target))
        if name == 'exporter':
            toolchain = target / 'lean-toolchain'
            expected = spec['lean_toolchain_override'] + '\n'
            if args.check:
                assert toolchain.read_text() == expected
            elif toolchain.read_text() != expected:
                if changed:
                    raise RuntimeError('Unrecognized exporter toolchain override')
                toolchain.write_text(expected)
        print(name + ': ' + spec['commit'], flush=True)
    # Restore the exact converter used for dependency-only diagnostic replays.
    converter = ROOT / 'scripts/handoff/arena_converter.py'
    raw = converter.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record['reference']['slice_converter_sha256']
    destination = ROOT / '_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py'
    if destination.exists():
        assert destination.read_bytes() == raw, 'Different existing slice converter'
    elif args.check:
        raise RuntimeError('Slice converter not installed')
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(raw)
    print('Pinned sources ready. No runtime build or Mathlib run was started.', flush=True)


if __name__ == '__main__':
    main()
