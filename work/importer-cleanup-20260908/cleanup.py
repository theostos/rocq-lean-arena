#!/usr/bin/env python3
"""Apply the audited importer branch cleanup, preserving commits and worktrees."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

OUT = Path(__file__).resolve().parent
BEFORE = json.loads((OUT / 'before.json').read_text())
PLAN = json.loads((OUT / 'plan.json').read_text())
REPO = Path(BEFORE['repository'])


def git(*args, cwd=REPO, data=None):
    return subprocess.check_output(['git', '-C', str(cwd), *args],
                                   input=data, text=True).strip()


def remote_heads():
    return {ref: sha for sha, ref in
            (line.split() for line in git('ls-remote', '--heads', 'fork').splitlines())}


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2) + '\n')


def capture(path):
    index = Path(git('rev-parse', '--path-format=absolute', '--git-path', 'index', cwd=path))
    return {
        'head': git('rev-parse', 'HEAD', cwd=path),
        'index_sha256': hashlib.sha256(index.read_bytes()).hexdigest(),
        'status': git('status', '--porcelain=v1', '--untracked-files=all', cwd=path),
    }


def archive_and_publish():
    assert remote_heads() == {r['ref']: r['sha'] for r in BEFORE['fork_heads']}
    refs = PLAN['delete_local'] + PLAN['delete_fork']
    # Also preserve the two old master tips before their fast-forward updates.
    for scope, entries in [('local', BEFORE['refs']), ('fork', BEFORE['fork_heads'])]:
        entry = next(r for r in entries if r['ref'] == 'refs/heads/master')
        refs.append({**entry, 'tag': f'refs/tags/archive/2026-09-08/{scope}/master'})
    commands = []
    for entry in refs:
        commands.append(f"create {entry['tag']} {entry['sha']}")
    git('update-ref', '--stdin', data='\n'.join(['start', *commands, 'prepare', 'commit', '']))
    write('archive-refs.json', refs)
    new_heads = {'refs/heads/' + b: git('rev-parse', b) for b in PLAN['publish']}
    new_heads['refs/heads/master'] = PLAN['fork_master_target']
    published_tags = {r['tag']: r['sha'] for r in refs if '/fork/' in r['tag']}
    old_heads = remote_heads()
    for ref in new_heads:
        assert ref == 'refs/heads/master' or ref not in old_heads, ref
    git('merge-base', '--is-ancestor', old_heads['refs/heads/master'], PLAN['fork_master_target'])
    args = ['push', '--atomic', 'fork']
    for ref, sha in {**published_tags, **new_heads}.items():
        args += [f'--force-with-lease={ref}:{old_heads.get(ref, "")}', f'{sha}:{ref}']
    output = git(*args)
    expected = {**old_heads, **new_heads}
    assert remote_heads() == expected
    tags = {ref: sha for sha, ref in (line.split() for line in
            git('ls-remote', '--tags', 'fork', 'archive/2026-09-08/fork/*').splitlines())}
    assert tags == published_tags
    write('published.json', {'heads': new_heads, 'archive_tags': published_tags,
                             'expected_heads_before_pruning': expected, 'output': output})
    print(f'Published {len(PLAN["publish"])} current branches and {len(published_tags)} archive tags.', flush=True)


def prune():
    published = json.loads((OUT / 'published.json').read_text())
    assert remote_heads() == published['expected_heads_before_pruning']
    for entry in PLAN['delete_local']:
        assert git('rev-parse', entry['ref']) == entry['sha'], entry['ref']
        assert git('rev-parse', entry['tag']) == entry['sha'], entry['tag']
    removed = {r['ref']: r for r in PLAN['delete_local']}
    detached = []
    # Change HEAD references only. In particular, do not run checkout/reset on
    # dirty or conflicted worktrees, or touch their files, index or merge state.
    for block in git('worktree', 'list', '--porcelain').split('\n\n'):
        fields = dict(line.split(' ', 1) if ' ' in line else (line, '')
                      for line in block.splitlines())
        if fields.get('branch') not in removed:
            continue
        path = Path(fields['worktree'])
        state = capture(path)
        assert state['head'] == removed[fields['branch']]['sha']
        git('update-ref', '--no-deref', '-m', 'Archive obsolete branch; preserve worktree and index',
            'HEAD', state['head'], state['head'], cwd=path)
        assert capture(path) == state, str(path)
        detached.append({'worktree': str(path), 'previous_branch': fields['branch'], **state})
        write('detached-worktrees.json', detached)
    commands = [f"delete {r['ref']} {r['sha']}" for r in PLAN['delete_local']]
    git('update-ref', '--stdin', data='\n'.join(['start', *commands, 'prepare', 'commit', '']))
    old_master = next(r['sha'] for r in BEFORE['refs'] if r['ref'] == 'refs/heads/master')
    git('merge-base', '--is-ancestor', old_master, PLAN['fork_master_target'])
    git('update-ref', 'refs/heads/master', PLAN['fork_master_target'], old_master)
    git('branch', '--set-upstream-to=upstream/master', 'master')
    args = ['push', '--atomic', 'fork']
    for entry in PLAN['delete_fork']:
        args += [f"--force-with-lease={entry['ref']}:{entry['sha']}", ':' + entry['ref']]
    git(*args)
    expected = {ref: sha for ref, sha in published['expected_heads_before_pruning'].items()
                if ref not in {r['ref'] for r in PLAN['delete_fork']}}
    assert remote_heads() == expected
    assert expected['refs/heads/pr/universe-instances'] == PLAN['preserved_pr70']
    actual_local = git('for-each-ref', '--format=%(refname:strip=2)', 'refs/heads').splitlines()
    assert sorted(actual_local) == PLAN['keep_local']
    for entry in detached:
        assert capture(Path(entry['worktree'])) == {
            key: entry[key] for key in ('head', 'index_sha256', 'status')}
    write('after.json', {'status': 'completed', 'local_branches': actual_local,
                        'fork_heads': expected, 'removed_local': len(PLAN['delete_local']),
                        'removed_fork': len(PLAN['delete_fork']), 'detached_worktrees': len(detached),
                        'worktree_heads_indexes_status_preserved': True,
                        'pr70_head_preserved': True})
    print(f'Removed {len(PLAN["delete_local"])} local and {len(PLAN["delete_fork"])} fork branches. '
          f'Preserved {len(detached)} detached worktrees.', flush=True)


if __name__ == '__main__':
    {'archive': archive_and_publish, 'prune': prune}[sys.argv[1]]()
