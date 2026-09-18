#!/usr/bin/env python3
"""Approve the tested two-view build, then resume the sealed 25M generation.

This is intentionally separate from the rejected historical resume.py. It
does not rewrite producer seals, change checking flags, or launch monitoring.
"""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

ALIGNMENT = HERE.parent / 'kernel-alignment-pass'
GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
GATES = ALIGNMENT / 'final-gates-typeops-checked-serial'
CONSUMER = ALIGNMENT / 'importer.y7jxl7hG'
WORKER_SHA = 'e17936ee0b3a7417d9452e083ccf9ef64cc1225eea856f2076a2456c6447bc3f'
CHECKER_SHA = '34488677886e8749696a3086edc2abbb5c9fb2da960881a682e7e01419305113'
UNIT = 'rocq-mathlib-alignment-5m-two-view.service'
RELEASE = HERE.parent / 'mathlib-two-view-release-20260914'


def require(condition, message):
    if not condition:
        raise chunks.Refused(message)


def main():
    certificate_path = HERE / 'two-view-consumer-certificate.json'
    approval_path = HERE / 'two-view-resume-approval.json'
    require(not certificate_path.exists() and not approval_path.exists(),
            'An approval already exists; inspect the run before trying again')
    require(not RELEASE.exists(), 'The immutable release directory already exists')
    require(not (GENERATION / 'PAUSE').exists(), 'A pause request is present')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__))}
    chunks.check_entries(inputs)
    evidence = {}

    def add(entries):
        for path, digest in entries.items():
            require(path not in inputs or inputs[path] == digest,
                    'Conflicting validation input: ' + path)
            inputs[path] = digest

    def read(path, current=True):
        record = json.loads(path.read_text())
        require(record.get('exit_code', 0) == 0, 'Failed validation: ' + str(path))
        if current and 'worker_sha256' in record:
            require(record['worker_sha256'] == WORKER_SHA,
                    'Validation used another worker: ' + str(path))
        for field in ('inputs', 'source_inputs', 'consumer_importer_inputs', 'outputs'):
            if field in record:
                add(record[field])
        add({str(path): chunks.sha(path)})
        evidence[str(path)] = record
        return record

    gate = read(GATES / 'passed.json')
    require(gate['native_fixtures'] == 17 and gate['legacy_fixtures'] == 20
            and {'typeops_application_conversions', 'checker_typed_conversion'}
                <= set(gate['runtime_unit_families']),
            'Incomplete native/legacy regression gate')
    legacy = read(GATES / 'legacy-regressions/passed.json')
    require(legacy['tests'] == 20 and len(legacy['results']) == 20
            and all(result['exit_code'] == 0 for result in legacy['results']),
            'Incomplete legacy regression evidence')
    runner = read(GATES / 'runner-tests.json')
    require(runner['tests'] >= 204 and runner['skipped'] <= 2,
            'Incomplete runner/resource/checkpoint tests')
    require(read(GATES / 'importer-regressions/passed.json')['tests'] == 44,
            'Incomplete importer regression gate')
    read(GATES / 'fresh-smoke/result.json')
    read(GATES / 'independent-check.json')
    strict = read(GATES / 'strict-independent-check.json')
    require(strict['strict_theory_profile'] and strict['strict_profile']['allow_definitional_uip']
            and strict['native_fixtures'] == 17 and not strict['admitted_dependencies'],
            'Incomplete strict native proof checking')
    policy = read(ALIGNMENT / 'strict-checker-typeops-checked/passed.json')
    require(len(policy['checks']) == 11, 'Incomplete strict-checker policy gate')

    lie = HERE.parent / 'mathlib-lie-trace-repro'
    controls = read(lie / 'proof-typeops-final/diagnostic-controls.json')
    require(not controls['environment'], 'A diagnostic conversion policy was enabled')
    combined = read(HERE / 'slice.json')
    require(combined['keep_all_proofs'] and combined['stats']['abstracted'] == 0,
            'Combined source slice has abstracted proofs')
    cases = ((lie, 'proof-prefix', 'proof-typeops-final', 'slice.json'),
             (HERE, 'sset-prefix', 'sset-typeops-final', 'sset-slice.json'),
             (HERE, 'derivative-prefix', 'derivative-typeops-final', 'derivative-slice.json'))
    for base, prefix, target, manifest_name in cases:
        manifest = read(base / manifest_name)
        require(manifest['keep_all_proofs'], 'Dependency proofs were abstracted')
        if base != lie:
            require(manifest['stats']['abstracted'] == 0,
                    'Extracted sub-slice has abstracted proofs')
        prefix_record = read(base / prefix / 'result.json', current=False)
        # The old prefix result is evidence about its own producer, not a claim
        # that the new worker rechecked those dependencies.
        prefix_artifact = base / prefix / (prefix_record['module'] + '.vo')
        add({str(prefix_artifact): prefix_record['vo_sha256']})
        record = read(base / target / 'result.json')
        read(base / target / 'invocation.json')
        artifact = base / target / (record['module'] + '.vo')
        add({str(artifact): record['vo_sha256']})
        independent = read(base / target / 'independent-target.json')
        require(independent['admitted_dependencies'] and not independent['strict'],
                'Unexpected independent continuation scope')

    original = HERE / 'riemannian-typeops-final'
    record = read(original / 'result.json')
    require(record['module'] == 'RiemannianWholeFrom25M', 'Wrong original-order replay')
    read(original / 'invocation.json')
    add({str(original / (record['module'] + '.vo')): record['vo_sha256']})
    independent = read(original / 'independent-original-order.json')
    require(independent['range'] == [25000001, 25525775]
            and independent['admitted_dependencies'] and not independent['strict'],
            'Incomplete original-order continuation checking')

    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    require(chunks.sha(plan_path) == '31b67da20277d497f23d2ca44c4a605dd11f47a914fb218caf09cb02cea34e7d',
            'Production plan changed')
    profile = chunks.generation_toolchain(plan)
    add(profile['inputs'])
    add({str(plan_path): chunks.sha(plan_path)})
    cursor = plan_path.parent / 'progress.json'
    progress = json.loads(cursor.read_text())
    require(progress['module'] == 'MathlibTo25000000' and progress['next_line'] == 25000001
            and progress['artifact_sha256'] ==
            '06c778feeab5f4d88e9a65880249e4c013abbc550f6a3cff8c3bd2ffe7fa4400',
            'Saved production cursor changed')
    require(plan['interval'] == 5000000 and plan['line_timeout'] == 1800
            and plan['memory_mib'] == 16384, 'Production limits changed')
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo25000000.vo')
    chunks.check_entries(inputs)
    # Keep the process-name expression short enough for pgrep's 15-character
    # comm-name check; conservatively match all worker suffixes.
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'],
                           stdout=subprocess.DEVNULL).returncode == 1,
            'A worker is still running')
    for unit in (UNIT, 'rocq-mathlib-alignment-5m-lie-sharing.service',
                 'rocq-mathlib-alignment-5m-except-conds.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'A production service is already running: ' + unit)

    # Validation checks live inputs above. Preserve that completed validation
    # as an immutable receipt, not perpetual dependencies on mutable worktree
    # source paths. Runtime importer inputs and the executing worker remain
    # directly checked by the adapter. Freeze the adapter too: future source
    # edits must not invalidate a previous producer's seal.
    RELEASE.mkdir()
    source_adapter = ALIGNMENT / 'consumer_toolchain.py'
    adapter_path = RELEASE / 'consumer_toolchain.py'
    shutil.copy2(source_adapter, adapter_path)
    require(chunks.sha(adapter_path) == inputs[str(source_adapter)],
            'The frozen adapter differs from the gated source')
    receipt_path = RELEASE / 'validation-receipt.json'
    chunks.save_json(receipt_path, {
        'format': 'rocq-completed-validation-v1', 'worker_sha256': WORKER_SHA,
        'checker_sha256': CHECKER_SHA, 'validated_inputs': inputs, 'evidence': evidence,
        'scope': 'Completed checks on these versions, not live worktree dependencies',
        'dependency_scope': 'Native dependencies rechecked; sealed Mathlib prefixes reused'})
    spec = importlib.util.spec_from_file_location('consumer_toolchain', adapter_path)
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    certificate = adapter.make_certificate(plan_path, CONSUMER,
        {str(receipt_path): chunks.sha(receipt_path)})
    require(certificate['worker_sha256'] == WORKER_SHA and all(
        path not in inputs or inputs[path] == digest
        for path, digest in certificate['inputs'].items()),
        'Runtime inputs changed after validation')
    chunks.save_json(certificate_path, certificate)
    certificate_hash = chunks.sha(certificate_path)
    # Check the exact process-local profile before any external launch.
    with adapter.installed_consumer(certificate_path, certificate_hash):
        rebuilt = chunks.generation_toolchain(plan)
        require(rebuilt['importer'] == str(CONSUMER), 'Consumer profile was not installed')

    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(adapter_path), '--certificate', str(certificate_path),
        '--sha256', certificate_hash]
    chunks.save_json(approval_path, {
        'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 25000001, 'service': UNIT, 'command': command,
        'certificate': str(certificate_path), 'certificate_sha256': certificate_hash,
        'validation_receipt': str(receipt_path),
        'inputs': inputs, 'notes': [
            'Producer artifacts and seals remain unchanged.',
            'Completed validation and the adapter are frozen; worktree edits do not rewrite history.',
            'Only an exact-source ABI rebuild of the importer is substituted.',
            'Existing launcher verifies and reloads the sealed 25M dependency chain.',
            'Native strict checks recheck dependencies; continuation checks reuse old proofs.',
            'Full Mathlib verification remains incomplete until EOF.',
            'No assistant monitoring after the startup check.']})
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming from line 25,000,001:', GENERATION, flush=True)


if __name__ == '__main__':
    main()
