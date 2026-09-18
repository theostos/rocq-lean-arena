#!/usr/bin/env python3
"""Resume at 45M after the focused Cotangent repair, without a full test suite."""
import difflib
import importlib.util
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
CONSUMER = HERE.parent / 'kernel-alignment-pass/importer.vnOgrcwY'
ADAPTER = HERE.parent / 'mathlib-srg-release-20260917-v1/consumer_toolchain.py'
WORKER_SHA = 'bb48befc1cd8dd8c14df1ae1db1822a8a5fab1ccb40c95e53a38e7f3082d65e3'
CHECKER_SHA = 'b8a115e119c3c99f2ef7a2ceb11a2c2e01acf0c3fba01f632c2ff20f9da81541'
UNIT = 'rocq-mathlib-alignment-5m-cotangent-v2.service'


def require(condition, message):
    if not condition:
        raise chunks.Refused(message)


def main():
    receipt_path = HERE / 'validation-receipt.json'
    certificate_path = HERE / 'consumer-certificate.json'
    approval_path = HERE / 'resume-approval.json'
    require(not any(p.exists() for p in (receipt_path, certificate_path, approval_path)),
            'A release already exists; inspect it before retrying')
    require(not (GENERATION / 'PAUSE').exists(), 'A pause request is present')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__)), str(ADAPTER): chunks.sha(ADAPTER)}
    evidence = {}

    def add(entries):
        for path, digest in entries.items():
            require(path not in inputs or inputs[path] == digest, 'Conflicting input: ' + path)
            inputs[path] = digest

    def read(path, historical=False):
        record = json.loads(path.read_text())
        require(record.get('exit_code', 0) == 0, 'Failed evidence: ' + str(path))
        if not historical:
            for field in ('inputs', 'outputs'):
                add(record.get(field, {}))
        add({str(path): chunks.sha(path)})
        evidence[str(path)] = record
        return record

    replay = read(HERE / 'replay.json')
    require(replay['keep_all_proofs'] and replay['stats']['abstracted'] == 0
            and replay['range'] == {'start': 2133792, 'end': 2133793},
            'Unexpected proof extraction or target')
    prefix = read(HERE / 'baseline-stream-prefix/result.json', historical=True)
    require(prefix['module'] == 'CotangentStreamPrefix', 'Wrong dependency prefix')
    add({str(HERE / 'baseline-stream-prefix/CotangentStreamPrefix.vo'): prefix['vo_sha256']})
    for directory, module in [('candidate-target-2', 'CotangentStreamTarget'),
                              ('applied-projection-tests-2', 'AppliedProjectionAliases')]:
        base = HERE / directory
        result = read(base / 'result.json')
        require(result['module'] == module and result['worker_sha256'] == WORKER_SHA,
                'Different worker/module used for validation')
        add({str(base / (module + '.vo')): result['vo_sha256']})
        invocation = read(base / 'invocation.json')
        require(str(CONSUMER / 'src') in invocation['command'], 'Different importer validated')
    independent = read(HERE / 'candidate-target-2/independent.json')
    require(independent['admitted_dependencies'] and not independent['strict']
            and independent['progress']['phase'] == 'passed',
            'Unexpected independent target-check scope')
    source = chunks.KERNEL / 'kernel/conversion.ml'
    baseline = HERE / 'conversion-baseline.ml'
    diff = ''.join(difflib.unified_diff(baseline.read_text().splitlines(keepends=True),
        source.read_text().splitlines(keepends=True),
        fromfile='production/kernel/conversion.ml', tofile='cotangent/kernel/conversion.ml'))
    require('let applied_projection_source' in diff and 'eq_usubs_fast e g' in diff,
            'Expected projection-order and syntax-context repair')
    add({str(source): chunks.sha(source), str(baseline): chunks.sha(baseline)})
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    require(chunks.sha(plan_path) ==
            '31b67da20277d497f23d2ca44c4a605dd11f47a914fb218caf09cb02cea34e7d'
            and (plan['interval'], plan['line_timeout'], plan['memory_mib']) ==
            (5000000, 1800, 16384), 'Production plan or limits changed')
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    require(progress['next_line'] == 45000001 and progress['module'] == 'MathlibTo45000000'
            and progress['artifact_sha256'] ==
            'c3cc9862c24b087a75c4e7f0e4dc5a76b66931624ade4be47eda5ebc3a2b3d51'
            and progress['reload_sha256'] ==
            '4955655c5b2a9a9d7c54904244684248c77a8664edfca26ed5744448d149058f',
            'Saved production cursor changed')
    predecessors = [c for c in plan['chunks'] if c['end'] <= 45000001]
    require(len(predecessors) == 9 and predecessors[-1]['end'] == 45000001,
            'Incomplete checkpoint chain')
    for chunk in predecessors:
        print('Verifying saved checkpoint seals:', chunk['module'], flush=True)
        require(chunks.verify_saved(plan_path.parent, chunk) is not None,
                'Invalid checkpoint: ' + chunk['module'])
    add(chunks.generation_toolchain(plan)['inputs'])
    add({str(plan_path): chunks.sha(plan_path)})
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo45000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'],
                           stdout=subprocess.DEVNULL).returncode == 1, 'A worker is running')
    for unit in (UNIT, 'rocq-mathlib-alignment-5m-srg-v1.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'Production service already running: ' + unit)
    chunks.save_json(receipt_path, {
        'format': 'rocq-completed-validation-v1', 'worker_sha256': WORKER_SHA,
        'checker_sha256': CHECKER_SHA, 'validated_inputs': inputs, 'evidence': evidence,
        'source_diff': diff, 'broader_regressions': 'Explicitly waived by the user',
        'scope': 'Exact Cotangent theorem, independent target check and targeted projection cases',
        'dependency_scope': 'Previously proof-checked slice prefix, foundation and 0–45M checkpoints reused',
        'full_mathlib_pass': False})
    spec = importlib.util.spec_from_file_location('cotangent_consumer', ADAPTER)
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    certificate = adapter.make_certificate(plan_path, CONSUMER,
        {str(receipt_path): chunks.sha(receipt_path)})
    require(certificate['worker_sha256'] == WORKER_SHA, 'Worker changed after validation')
    chunks.save_json(certificate_path, certificate)
    certificate_hash = chunks.sha(certificate_path)
    with adapter.installed_consumer(certificate_path, certificate_hash):
        require(chunks.generation_toolchain(plan)['importer'] == str(CONSUMER),
                'Consumer profile not installed')
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(ADAPTER), '--certificate', str(certificate_path),
        '--sha256', certificate_hash]
    chunks.save_json(approval_path, {
        'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 45000001, 'service': UNIT, 'command': command,
        'certificate': str(certificate_path), 'certificate_sha256': certificate_hash,
        'validation_receipt': str(receipt_path), 'inputs': inputs,
        'notes': ['Full suite skipped at explicit user request.',
                  'Producer checkpoints and all checking/resource limits unchanged.',
                  'Original serial importer pipeline; only an ABI rebuild of its existing source.',
                  'No assistant monitoring after the startup check.']})
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming from line 45,000,001:', GENERATION, flush=True)


if __name__ == '__main__':
    main()
