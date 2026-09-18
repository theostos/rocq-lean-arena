#!/usr/bin/env python3
"""Resume the sealed 25M chain after the local-sharing retry passes its gates."""
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
GATES = HERE.parent / 'kernel-alignment-pass/final-gates-lie-sharing-retry'
UNIT = 'rocq-mathlib-alignment-5m-lie-sharing.service'
WORKER_SHA = 'ce98e4acc636eb5506b2294f6a6edb16bbf65b8503be2a0f09d8b8041cee28fb'
CHECKER_SHA = '4fdc763343aadf5673433783f536a45502ddd2e36ca35392f9e38c4bad4d1c0b'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    approval = HERE / 'resume-approval.json'
    require(not approval.exists(), 'Approval already exists; inspect the run first')
    require(not (GENERATION / 'PAUSE').exists(), 'Pause request is present; not removed')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__))}
    chunks.check_entries(inputs)
    records = [GATES / 'passed.json', GATES / 'independent-check.json',
        GATES / 'strict-independent-check.json', GATES / 'fresh-smoke/result.json',
        GATES / 'importer-regressions/passed.json', HERE / 'proof-final/result.json',
        HERE / 'proof-final/invocation.json', HERE / 'proof-final/diagnostic-controls.json',
        HERE / 'proof-final/independent-target.json', HERE / 'slice.json',
        HERE.parent / 'kernel-alignment-pass/strict-checker-lie-sharing/passed.json']
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
    require(json.loads((GATES / 'importer-regressions/passed.json').read_text())['tests'] == 44,
            'Incomplete importer regression gate')
    strict = json.loads((GATES / 'strict-independent-check.json').read_text())
    require(strict['strict_theory_profile'] and strict['strict_profile']['allow_definitional_uip']
            and strict['native_fixtures'] == 15 and not strict['admitted_dependencies'],
            'Incomplete independent strict native checking')
    require(json.loads((HERE / 'slice.json').read_text())['keep_all_proofs'],
            'Theorem slice must retain every dependency proof')
    require(not json.loads((HERE / 'proof-final/diagnostic-controls.json').read_text())['environment'],
            'Diagnostic conversion controls enabled in final replay')
    prefix_record = HERE / 'proof-prefix/result.json'
    prefix = json.loads(prefix_record.read_text())
    require(prefix['exit_code'] == 0 and prefix['vo_sha256'] ==
            '58e7b89ab0fe3b8c10b26a0b494ae4af9bdc264991968e1165131610fb426c0e',
            'Proof-preserving prefix changed')
    inputs[str(prefix_record)] = chunks.sha(prefix_record)
    target = HERE / 'proof-final/ProofTarget.vo'
    inputs[str(target)] = json.loads((HERE / 'proof-final/result.json').read_text())['vo_sha256']
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    chunks.check_entries(profile['inputs'])
    inputs.update(profile['inputs'])
    inputs[str(plan_path)] = chunks.sha(plan_path)
    progress_path = plan_path.parent / 'progress.json'
    progress = json.loads(progress_path.read_text())
    require(progress['module'] == 'MathlibTo25000000' and progress['next_line'] == 25000001,
            'Saved cursor changed; inspect it before resuming')
    require(progress['artifact_sha256'] ==
            '06c778feeab5f4d88e9a65880249e4c013abbc550f6a3cff8c3bd2ffe7fa4400',
            '25M checkpoint changed')
    require(plan['interval'] == 5000000 and plan['line_timeout'] == 1800
            and plan['memory_mib'] == 16384, 'Existing run policy changed')
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo25000000.vo')
    chunks.check_entries(inputs)
    for unit in (UNIT, 'rocq-mathlib-alignment-5m-except-conds.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'A run service is already active: ' + unit)
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(ROOT / 'scripts/mathlib_ndjson_loop.py'), 'run',
        '--directory', str(GENERATION), '--interval', '5000000',
        '--line-timeout', '1800', '--memory-mib', '16384', '--importer', profile['importer']]
    chunks.save_json(approval, {'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 25000001, 'service': UNIT, 'command': command, 'inputs': inputs,
        'notes': ['Existing producer seals and global sharing flag are unchanged.',
                  'Launcher verifies seals and freshly reloads 25M before continuing.',
                  'Independent strict native checks recheck all dependencies.',
                  'Independent target check reuses the separately typechecked proof-preserving prefix.',
                  'Full Mathlib verification remains incomplete until EOF.',
                  'No assistant monitoring after the startup check.']})
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming existing generation from line 25,000,001:', GENERATION, flush=True)


if __name__ == '__main__':
    main()
