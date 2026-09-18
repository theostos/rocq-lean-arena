#!/usr/bin/env python3
"""Resume the existing 20M chain only after this repair's gates pass."""
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
GATES = HERE.parent / 'kernel-alignment-pass/final-gates-except-conds-2'
UNIT = 'rocq-mathlib-alignment-5m-except-conds.service'
WORKER_SHA = '11acf90892e197e1f4a61ac756906b59225e35189d837c223786266bb400f15c'
CHECKER_SHA = 'fa129d2d059ef132fcdf6e9e3ba767a85bbd8b1dc596c4cd52cdd445ba450b99'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    approval = HERE / 'resume-approval.json'
    require(not approval.exists(), 'Resume approval already exists; inspect the run first')
    require(not (GENERATION / 'PAUSE').exists(), 'A pause request is present; not removed')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__))}
    chunks.check_entries(inputs)
    records = [GATES / 'passed.json', GATES / 'independent-check.json',
        GATES / 'strict-independent-check.json',
        GATES / 'fresh-smoke/result.json', GATES / 'importer-regressions/passed.json',
        HERE / 'native-candidate/result.json', HERE / 'slice-candidate/result.json',
        HERE / 'slice-candidate/invocation.json',
        HERE / 'slice-candidate/compatibility-independent-final.json',
        HERE / 'slice.json',
        HERE.parent / 'kernel-alignment-pass/strict-checker-except-conds/passed.json']
    for path in records:
        record = json.loads(path.read_text())
        require(record.get('exit_code', 0) == 0, 'Failed validation: ' + str(path))
        if 'worker_sha256' in record:
            require(record['worker_sha256'] == WORKER_SHA,
                    'Validation used another worker: ' + str(path))
        for field in ('inputs', 'source_inputs', 'consumer_importer_inputs', 'outputs'):
            if field in record:
                chunks.check_entries(record[field])
                inputs.update(record[field])
        inputs[str(path)] = chunks.sha(path)
    gate = json.loads((GATES / 'passed.json').read_text())
    require(gate['native_fixtures'] == 15 and gate['legacy_fixtures'] == 20,
            'Incomplete kernel regression gate')
    importer_gate = json.loads((GATES / 'importer-regressions/passed.json').read_text())
    require(importer_gate['tests'] == 44, 'Incomplete importer regression gate')
    strict = json.loads((GATES / 'strict-independent-check.json').read_text())
    require(strict['strict_theory_profile'] and strict['strict_profile']['allow_definitional_uip']
            and strict['native_fixtures'] == 15 and not strict['admitted_dependencies'],
            'Incomplete independent strict native checking')
    require(json.loads((HERE / 'slice.json').read_text())['keep_all_proofs'],
            'Theorem slice must retain every dependency proof')
    artifact = HERE / 'slice-candidate/Slice.vo'
    inputs[str(artifact)] = json.loads((HERE / 'slice-candidate/result.json').read_text())['vo_sha256']
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    chunks.check_entries(profile['inputs'])
    inputs.update(profile['inputs'])
    inputs[str(plan_path)] = chunks.sha(plan_path)
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    require(progress['module'] == 'MathlibTo20000000' and progress['next_line'] == 20000001,
            'The saved cursor changed; inspect it before resuming')
    require(plan['interval'] == 5000000 and plan['line_timeout'] == 1800
            and plan['memory_mib'] == 16384, 'Existing run policy changed')
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo20000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', UNIT]).returncode != 0,
            'Resume service already active')
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(ROOT / 'scripts/mathlib_ndjson_loop.py'), 'run',
        '--directory', str(GENERATION), '--interval', '5000000',
        '--line-timeout', '1800', '--memory-mib', '16384', '--importer', profile['importer']]
    chunks.save_json(approval, {'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 20000001, 'service': UNIT, 'command': command, 'inputs': inputs,
        'notes': ['Existing producer seals are not rewritten.',
                  'Launcher verifies all seals and freshly reloads 20M before continuing.',
                  'Original importer compatibility flags are unchanged.',
                  'No assistant monitoring after the startup check.']})
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming existing generation from line 20,000,001:', GENERATION, flush=True)


if __name__ == '__main__':
    main()
