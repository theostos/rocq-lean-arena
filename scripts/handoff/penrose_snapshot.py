#!/usr/bin/env python3
"""Snapshot the qualified Penrose delta, without touching either live index.

Transfer the resulting incremental bundles over SSH; this does not publish to
GitHub, copy generated runtimes, or launch a remote build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BRANCH = 'handoff/mathlib-20260918-penrose'
BASES = {'kernel': 'd17b66af824e344393b126e57fbcec99174f926a',
         'arena': '2abce41a8ebd9f4ec10959f42d2f4d1b01b6b55f'}
KERNEL_FILES = ('kernel/hConstr.ml', 'kernel/vars.ml', 'kernel/typeops.ml',
                'kernel/constr.ml', 'checker/validate.ml', 'checker/mod_checking.ml')


def git(repo, *args, **kwargs):
    return subprocess.check_output(['git', '-C', str(repo), *args], **kwargs)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def arena_files():
    for name in ('HANDOFF.md', 'docs/handoff-20260918.json',
                 'docs/mathlib-handoff-review.md', 'scripts/handoff/penrose_snapshot.py'):
        yield ROOT / name
    repro = ROOT / 'work/mathlib-penrose-repro'
    for path in repro.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        relative = path.relative_to(repro)
        # Never copy native test build directories, generated proof data, or binaries.
        if len(relative.parts) > 1 and not relative.parts[0].startswith(
                ('candidate-', 'baseline-prefix', 'fresh-small-', 'diagnostic-target')):
            continue
        if path.suffix in {'.py', '.sh', '.ml', '.mli', '.md', '.v', '.json', '.log'} \
                and path.stat().st_size <= 2 * 1024**2:
            yield path
    padic = ROOT / 'work/mathlib-padic-repro/penrose-regression-2'
    for path in padic.iterdir():
        if path.is_file() and not path.is_symlink() and path.suffix in {'.v', '.json', '.log'} \
                and path.stat().st_size <= 2 * 1024**2:
            yield path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('component', choices=BASES)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    repo = ROOT / '_worktrees/rocq/compact-peano-view' if args.component == 'kernel' else ROOT
    paths = [repo / name for name in KERNEL_FILES] if args.component == 'kernel' else list(arena_files())
    base, ref = BASES[args.component], 'refs/heads/' + BRANCH
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    bundle, receipt = output / (args.component + '.bundle'), output / (args.component + '-source.json')
    assert not bundle.exists() and not receipt.exists()
    assert subprocess.run(['git', '-C', str(repo), 'show-ref', '--verify', '--quiet', ref]).returncode == 1
    head = git(repo, 'rev-parse', 'HEAD')
    index = Path(git(repo, 'rev-parse', '--path-format=absolute', '--git-path', 'index').decode().strip())
    index_before = index.read_bytes() if index.exists() else None
    validation = json.loads((ROOT / 'work/mathlib-penrose-repro/validation-receipt.json').read_text())
    inventory = {}
    with tempfile.TemporaryDirectory(prefix='penrose-source-index-') as temporary:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temporary) / 'index'))
        git(repo, 'read-tree', base, env=env)
        for path in sorted(set(paths)):
            assert path.is_file() and not path.is_symlink()
            name, data = str(path.relative_to(repo)), path.read_bytes()
            sha = digest(data)
            if args.component == 'kernel':
                assert validation['validated_inputs'][str(path)] == sha, name
            mode = '100755' if path.stat().st_mode & 0o111 else '100644'
            blob = git(repo, 'hash-object', '-w', '--stdin', input=data).decode().strip()
            git(repo, 'update-index', '--add', '--cacheinfo', mode, blob, name, env=env)
            inventory[name] = dict(sha256=sha, size=len(data), mode=mode)
        tree = git(repo, 'write-tree', env=env).decode().strip()
        commit = git(repo, '-c', 'user.name=Codex', '-c', 'user.email=codex@localhost',
                     'commit-tree', tree, '-p', base,
                     input=('Preserve qualified Penrose traversal repair: ' + args.component + '\n').encode(),
                     env=env).decode().strip()
        for name, entry in inventory.items():
            assert digest(git(repo, 'show', commit + ':' + name)) == entry['sha256']
            assert digest((repo / name).read_bytes()) == entry['sha256']
        changed = git(repo, 'diff-tree', '--no-commit-id', '--name-only', '-r', commit).decode().splitlines()
        assert set(changed) <= set(inventory)
        if args.component == 'kernel':
            assert set(changed) == set(KERNEL_FILES)
        git(repo, 'update-ref', ref, commit, '0' * 40)
    assert git(repo, 'rev-parse', 'HEAD') == head
    assert (index.read_bytes() if index.exists() else None) == index_before
    git(repo, 'bundle', 'create', str(bundle), ref, '^' + base)
    git(repo, 'bundle', 'verify', str(bundle))
    result = dict(component=args.component, base=base, commit=commit, branch=BRANCH,
                  repository=str(repo), files=inventory, changed=changed,
                  bundle_sha256=digest(bundle.read_bytes()), live_index_unchanged=True,
                  github_published=False, scope='Source and historical small evidence; no remote validation')
    with receipt.open('x') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(json.dumps({k: result[k] for k in ('component', 'commit', 'bundle_sha256')}) )


if __name__ == '__main__':
    main()
