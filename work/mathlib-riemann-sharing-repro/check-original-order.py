#!/usr/bin/env python3
"""Recheck the new original-order module, reusing its sealed dependency chain.

This is an independent checker process with no importer plugin. It is NOT a
fresh recheck of the first 25M lines; those dependency artifacts stay inputs.
"""
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct


def main():
    directory = Path(sys.argv[1]).resolve(strict=True)
    if directory.parent != HERE:
        raise ValueError('Expected an original-order replay directory')
    result_path = directory / 'result.json'
    record = json.loads(result_path.read_text())
    if record['exit_code'] != 0 or record['module'] != 'RiemannianWholeFrom25M':
        raise ValueError('Expected a successful complete original-order replay')
    invocation_path = directory / 'invocation.json'
    inputs = dict(json.loads(invocation_path.read_text())['inputs'])
    artifact = directory / (record['module'] + '.vo')
    if chunks.sha(artifact) != record['vo_sha256']:
        raise ValueError('Changed replay artifact')
    generation = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
    plan_path = generation / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    predecessors = [c for c in plan['chunks'] if c['end'] <= 25000001]
    if len(predecessors) != 5 or predecessors[-1]['end'] != 25000001:
        raise ValueError('Incomplete 25M dependency chain')
    for chunk in predecessors:
        path = plan_path.parent / (chunk['module'] + '.vo')
        if inputs.get(str(path)) != chunks.sha(path):
            raise ValueError('Unbound dependency: ' + str(path))
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    for path in (checker, Path(__file__), artifact, result_path, invocation_path,
                 artifact.with_suffix('.v')):
        inputs[str(path)] = chunks.sha(path)
    chunks.check_entries(inputs)
    command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '1800s',
        str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
        '-R', str(direct.checking.STDLIB), 'Stdlib',
        '-Q', str(generation / 'foundation'), 'LeanImport',
        '-Q', str(plan_path.parent), '', '-Q', str(directory), '',
        '-o', '-norec', record['module']]
    started = time.monotonic()
    with (directory / 'independent-original-order.log').open('x') as log:
        checked = subprocess.run(command, env=direct.environment(16384),
                                 stdout=log, stderr=subprocess.STDOUT)
    chunks.check_entries(inputs)
    chunks.save_json(directory / 'independent-original-order.json', {
        'exit_code': checked.returncode, 'wall_seconds': time.monotonic() - started,
        'command': command, 'inputs': inputs, 'admitted_dependencies': True,
        'strict': False, 'range': [25000001, 25525775],
        'scope': 'Recheck all new proofs; reuse sealed proofs from the first 25M lines'})
    return checked.returncode


if __name__ == '__main__':
    raise SystemExit(main())
