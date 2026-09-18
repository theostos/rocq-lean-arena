#!/usr/bin/env python3
"""Resume 25M only after balanced-sharing proof replays and gates pass."""
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
ALIGNMENT = HERE.parent / 'kernel-alignment-pass'
GATES = ALIGNMENT / 'final-gates-balanced-sharing'
LIE = HERE.parent / 'mathlib-lie-trace-repro'
UNIT = 'rocq-mathlib-alignment-5m-balanced-sharing.service'
WORKER_SHA = '3adbcb1ad9ff02a21a404581f6bc902d7107fc7d799f1c9f8bb067b3f291e0a7'
CHECKER_SHA = 'ea0103942bd4bafbaa6f9a8b61ef9f9d728a72320c1c8d6917e0bffc8d18cd4a'

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

    def read_checked(path):
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
        return record

    gate = read_checked(GATES / 'passed.json')
    require(gate['native_fixtures'] == 15 and gate['legacy_fixtures'] == 20,
            'Incomplete kernel regression gate')
    require(read_checked(GATES / 'importer-regressions/passed.json')['tests'] == 44,
            'Incomplete importer regression gate')
    read_checked(GATES / 'fresh-smoke/result.json')
    read_checked(GATES / 'independent-check.json')
    strict = read_checked(GATES / 'strict-independent-check.json')
    require(strict['strict_theory_profile'] and strict['strict_profile']['allow_definitional_uip']
            and strict['native_fixtures'] == 15 and not strict['admitted_dependencies'],
            'Incomplete independent strict native checking')
    policy = read_checked(ALIGNMENT / 'strict-checker-balanced-sharing/passed.json')
    require(len(policy['checks']) == 11, 'Incomplete strict-checker policy gate')
    require(not read_checked(LIE / 'proof-balanced-sharing/diagnostic-controls.json')['environment'],
            'Diagnostic conversion controls enabled in final Lie replay')

    for base, prefix, target in ((HERE, 'proof-prefix', 'proof-targets'),
                                (LIE, 'proof-prefix', 'proof-balanced-sharing')):
        manifest = read_checked(base / 'slice.json')
        require(manifest['keep_all_proofs'], 'Dependency proofs must not be abstracted')
        for folder in (base / prefix, base / target):
            if folder == LIE / 'proof-prefix':
                # This historical prefix has a different, recorded producer.
                record_path = folder / 'result.json'
                record = json.loads(record_path.read_text())
                require(record['exit_code'] == 0 and record['vo_sha256'] ==
                        '58e7b89ab0fe3b8c10b26a0b494ae4af9bdc264991968e1165131610fb426c0e',
                        'Historical Lie proof prefix changed')
                inputs[str(record_path)] = chunks.sha(record_path)
            else:
                record = read_checked(folder / 'result.json')
                read_checked(folder / 'invocation.json')
            artifact = folder / (record['module'] + '.vo')
            inputs[str(artifact)] = record['vo_sha256']
        independent = read_checked(base / target / 'independent-target.json')
        require(independent['admitted_dependencies'] and not independent['strict'],
                'Unexpected independent target-check scope')
    require(json.loads((HERE / 'slice.json').read_text())['stats']['abstracted'] == 0,
            'Combined slice has abstracted dependency proofs')

    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    profile = chunks.generation_toolchain(plan)
    chunks.check_entries(profile['inputs'])
    inputs.update(profile['inputs'])
    inputs[str(plan_path)] = chunks.sha(plan_path)
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    require(progress['module'] == 'MathlibTo25000000' and progress['next_line'] == 25000001,
            'Saved cursor changed; inspect it before resuming')
    require(progress['artifact_sha256'] ==
            '06c778feeab5f4d88e9a65880249e4c013abbc550f6a3cff8c3bd2ffe7fa4400',
            '25M checkpoint changed')
    require(plan['interval'] == 5000000 and plan['line_timeout'] == 1800
            and plan['memory_mib'] == 16384, 'Existing run policy changed')
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo25000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['pgrep', '-x', r'rocqworker(\.exe)?'],
                           stdout=subprocess.DEVNULL).returncode == 1,
            'A worker is already running')
    for unit in (UNIT, 'rocq-mathlib-alignment-5m-lie-sharing.service',
                 'rocq-mathlib-alignment-5m-except-conds.service'):
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
        'notes': ['Existing checkpoint seals and global sharing flag are unchanged.',
                  'Launcher verifies seals and freshly reloads 25M before continuing.',
                  'Native strict checks recheck all dependencies.',
                  'Independent continuation checks reuse separately checked proof prefixes.',
                  'Full Mathlib verification remains incomplete until EOF.',
                  'No assistant monitoring after the startup check.']})
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming from line 25,000,001:', GENERATION, flush=True)

if __name__ == '__main__':
    main()
