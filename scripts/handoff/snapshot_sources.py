#!/usr/bin/env python3
"""Create reviewable source snapshots with a private Git index, never a checkout.

No push is performed here. The caller reviews the inventory and publishes the
new, explicitly named refs separately. Existing refs and the real index stay put.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BRANCH = 'handoff/mathlib-20260918'
IDENTITY = ['-c', 'user.name=Codex', '-c', 'user.email=codex@localhost']


def git(repo, *args, **kw):
    return subprocess.check_output(['git', '-C', str(repo), *args], **kw)


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def paths(repo, *args):
    return [Path(os.fsdecode(p)) for p in git(repo, 'ls-files', '-z', *args).split(b'\0') if p]


def arena_extra(root):
    """Source/evidence only: no binaries, exports, active stages, or chat history."""
    if (root / 'HANDOFF.md').is_file():
        yield Path('HANDOFF.md')
    for top in ('docs', 'scripts', 'checkers', 'work'):
        for folder, dirs, files in os.walk(root / top):
            dirs[:] = [d for d in dirs if not (
                d.startswith(('.', 'importer.', 'handoff-', 'pr78-', 'validation-staging'))
                or d in {'_build', '_deps', '_worktrees', '__pycache__', 'checkpoints', 'attempts',
                         'node_modules', 'rootfs', 'payload', 'runs'})]
            for name in files:
                p = Path(folder) / name
                if p.is_symlink() or not p.is_file() or p.stat().st_size > 2 * 1024**2:
                    continue
                code = p.suffix in {'.md', '.py', '.sh', '.ml', '.mli', '.lean', '.gdb'}
                fixture = (p.suffix == '.v' and p.stat().st_size < 128 * 1024
                           and not name.startswith(('Prefix', 'MathlibTo', 'Full')))
                evidence = p.suffix == '.json' and (top == 'docs' or any(s in name.lower() for s in (
                    'result', 'receipt', 'validation', 'review-stack', 'source-snapshot')))
                if code or fixture or evidence:
                    yield p.relative_to(root)


def snapshot(repo, tree, branch, extra, message, output):
    ref = 'refs/heads/' + branch
    subprocess.run(['git', '-C', str(repo), 'check-ref-format', ref], check=True)
    if subprocess.run(['git', '-C', str(repo), 'show-ref', '--verify', '--quiet', ref]).returncode == 0:
        raise RuntimeError('Ref already exists: ' + ref)
    head = git(repo, 'rev-parse', 'HEAD').decode().strip()
    names = sorted(set(paths(repo) + list(extra)))
    if tree != repo:
        # The staged importer supplies runtime source, not a new fixture archive.
        # Preserve the base commit's LFS-managed dumps without restaging them.
        names = [p for p in names if p.parts[0] != 'dumps']
    inventory = {}
    for p in names:
        source = tree / p
        if source.is_symlink():
            inventory[str(p)] = {'symlink': os.readlink(source)}
        elif source.is_file():
            inventory[str(p)] = {'sha256': sha(source), 'size': source.stat().st_size}
        elif source.exists():
            raise RuntimeError('Unexpected source directory: ' + str(source))
    if output.exists():
        raise RuntimeError('Receipt already exists: ' + str(output))
    index_path = Path(git(repo, 'rev-parse', '--path-format=absolute', '--git-path', 'index').decode().strip())
    index_before = sha(index_path) if index_path.exists() else None
    with tempfile.TemporaryDirectory(prefix='mathlib-source-index-') as temp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temp) / 'index'), GIT_WORK_TREE=str(tree))
        git(repo, 'read-tree', head, env=env)
        # -A only for the explicitly inventoried paths; no broad work/ staging.
        git(repo, 'add', '-f', '-A', '--pathspec-from-file=-', '--pathspec-file-nul',
            input=b'\0'.join(os.fsencode(p) for p in names) + b'\0', env=env)
        tree_id = git(repo, 'write-tree', env=env).decode().strip()
        commit = git(repo, *IDENTITY, 'commit-tree', tree_id, '-p', head,
                     input=(message + '\n').encode(), env=env).decode().strip()
        # Ensure the checked-in blobs reproduce the captured source bytes.
        for name, entry in inventory.items():
            raw = git(repo, 'show', commit + ':' + name)
            if 'symlink' in entry and os.fsdecode(raw) != entry['symlink']:
                raise RuntimeError('Git symlink mismatch: ' + name)
            if 'sha256' in entry and hashlib.sha256(raw).hexdigest() != entry['sha256']:
                raise RuntimeError('Git filter/source mismatch: ' + name)
            if 'sha256' in entry and sha(tree / name) != entry['sha256']:
                raise RuntimeError('Source changed during snapshot: ' + name)
        git(repo, 'update-ref', ref, commit, '0' * 40)
    assert git(repo, 'rev-parse', 'HEAD').decode().strip() == head
    assert (sha(index_path) if index_path.exists() else None) == index_before
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as f:
        json.dump(dict(repository=str(repo), source_tree=str(tree), base=head, commit=commit,
                       branch=branch, files=inventory, live_index_unchanged=True), f, indent=2)
        f.write('\n')
    print(json.dumps(dict(commit=commit, branch=branch, files=len(inventory), receipt=str(output))))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('component', choices=['kernel', 'importer', 'arena'])
    p.add_argument('--branch', default=BRANCH)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    if a.component == 'kernel':
        repo = tree = ROOT / '_worktrees/rocq/compact-peano-view'
        extra = [x for x in paths(repo, '--others', '--exclude-standard')
                 if x.parts[0] == 'test-suite' and x.suffix in {'.ml', '.mli', '.v'}]
    elif a.component == 'importer':
        repo = ROOT / '_worktrees/rocq-lean-import/cslib-ndjson'
        tree = ROOT / 'work/kernel-alignment-pass/importer.rEXkanSl'
        extra = []
    else:
        repo = tree = ROOT
        extra = arena_extra(ROOT)
    snapshot(repo, tree, a.branch, extra,
             'Snapshot validated Mathlib runtime and review evidence (2026-09-18): ' + a.component,
             a.output.resolve())


if __name__ == '__main__':
    main()
