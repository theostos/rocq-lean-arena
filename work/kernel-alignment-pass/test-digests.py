#!/usr/bin/env python3
"""Check that ordinary loading rejects changed dependencies, including old bypass flags."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_cslib_ndjson as direct

WORKER = ROOT / '_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe'


def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def main():
    directory = Path(tempfile.mkdtemp(prefix='digest-tests.', dir=HERE))
    print(directory, flush=True)
    active, changed = directory / 'active', directory / 'changed'
    active.mkdir()
    changed.mkdir()
    fixtures = HERE / 'digest-fixtures'
    for name in ('B.v', 'Load.v'):
        shutil.copy2(fixtures / name, active / name)
    shutil.copy2(fixtures / 'original/A.v', active / 'A.v')
    shutil.copy2(fixtures / 'changed/A.v', changed / 'A.v')
    worker_hash = sha(WORKER)
    results = []

    def compile(source, label, bypass=None, reject=False):
        env = direct.environment(2048)
        env.pop('ROCQ_DIAGNOSTIC_IGNORE_VO_DIGEST', None)
        if bypass is not None:
            env['ROCQ_DIAGNOSTIC_IGNORE_VO_DIGEST'] = bypass
        command = ['bash', str(direct.checking.GUARD), 'timeout', '30s',
                   str(WORKER), '--kind=compile', '-coqlib', env['COQLIB'], '-q',
                   '-bytecode-compiler', 'no', '-Q', str(source.parent), 'DigestCase',
                   str(source)]
        log = directory / (label + '.log')
        with log.open('x') as output:
            result = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT)
        diagnostic = log.read_text()
        expected = (result.returncode == 1 and 'inconsistent assumptions' in diagnostic
                    if reject else result.returncode == 0)
        results.append({'label': label, 'code': result.returncode, 'passed': expected})
        print(label, result.returncode, flush=True)
        if not expected:
            raise RuntimeError(diagnostic)

    compile(active / 'A.v', 'original')
    compile(active / 'B.v', 'dependent')
    compile(active / 'Load.v', 'matching-control')
    compile(changed / 'A.v', 'replacement')
    assert sha(active / 'A.vo') != sha(changed / 'A.vo')
    # Only this test's generated dependency is replaced. Preserve its original
    # bytes for inspection; no checkpoint, source or existing user file changes.
    shutil.copy2(active / 'A.vo', directory / 'original-A.vo')
    shutil.copy2(changed / 'A.vo', active / 'A.vo')
    for label, value in [('unset', None), ('zero', '0'), ('one', '1')]:
        compile(active / 'Load.v', 'mismatch-' + label, value, reject=True)
    assert worker_hash == sha(WORKER)
    with (directory / 'passed.json').open('x') as output:
        json.dump({'worker_sha256': worker_hash, 'results': results}, output, indent=2)


if __name__ == '__main__':
    main()
