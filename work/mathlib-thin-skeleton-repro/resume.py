#!/usr/bin/env python3
"""Resume the existing 10M chain only after this repair's validation succeeds."""
import json
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
GATES = HERE.parent / 'kernel-alignment-pass/final-gates-21'
UNIT = 'rocq-mathlib-alignment-5m-20260913-thin-skeleton.service'
WORKER_SHA = '27e6a824c34bf8256a73e778023f78ed2061b573a51afc6653151cf59f800bc8'
CHECKER_SHA = '79ad54a5485e2d4c5001347a45cc396bcb8a5bdd7b0d6fe92a889cec6ee50971'

def main():
    approval = HERE / 'resume-approval.json'
    if approval.exists():
        raise RuntimeError('This repair has already issued a resume approval; inspect the run first')
    if (GENERATION / 'PAUSE').exists():
        raise RuntimeError('A pause request is present; it has not been removed')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__))}
    chunks.check_entries(inputs)
    records = [GATES / 'passed.json', GATES / 'independent-check.json',
        GATES / 'strict-independent-check.json', HERE / 'slice-final/result.json',
        HERE / 'slice-final/compatibility-independent.json',
        HERE.parent / 'kernel-alignment-pass/strict-checker-6/passed.json']
    for path in records:
        record = json.loads(path.read_text())
        if record.get('exit_code', 0) != 0:
            raise RuntimeError('Failed validation: ' + str(path))
        if 'worker_sha256' in record and record['worker_sha256'] != WORKER_SHA:
            raise RuntimeError('Validation used another worker: ' + str(path))
        for field in ('inputs', 'source_inputs', 'consumer_importer_inputs'):
            if field in record:
                chunks.check_entries(record[field])
                inputs.update(record[field])
        inputs[str(path)] = chunks.sha(path)
    gate = json.loads(records[0].read_text())
    assert gate['native_fixtures'] == 14 and gate['legacy_fixtures'] == 20
    strict = json.loads((GATES / 'strict-independent-check.json').read_text())
    assert strict['strict_theory_profile'] and strict['strict_profile']['allow_definitional_uip']
    artifact = HERE / 'slice-final/Slice.vo'
    inputs[str(artifact)] = json.loads((HERE / 'slice-final/result.json').read_text())['vo_sha256']
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    chunks.check_entries(profile['inputs'])
    inputs.update(profile['inputs'])
    inputs[str(plan_path)] = chunks.sha(plan_path)
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    assert progress['module'] == 'MathlibTo10000000' and progress['next_line'] == 10000001
    assert plan['interval'] == 5000000 and plan['line_timeout'] == 1800
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo10000000.vo')
    chunks.check_entries(inputs)
    if subprocess.run(['systemctl', '--user', 'is-active', '--quiet', UNIT]).returncode == 0:
        raise RuntimeError('Resume service already active')
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(ROOT / 'scripts/mathlib_ndjson_loop.py'), 'run',
        '--directory', str(GENERATION), '--interval', '5000000',
        '--line-timeout', '1800', '--memory-mib', '16384', '--importer', profile['importer']]
    chunks.save_json(approval, {'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 10000001, 'service': UNIT, 'command': command, 'inputs': inputs,
        'notes': ['Existing producer seals are not rewritten.',
                  'Launcher verifies all seals and freshly reloads 10M before continuing.',
                  'Original importer compatibility flags are unchanged.',
                  'No assistant monitoring after the startup check.']})
    env = {key: value for key, value in os.environ.items()
        if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming existing generation from line 10,000,001:', GENERATION, flush=True)

if __name__ == '__main__':
    main()
