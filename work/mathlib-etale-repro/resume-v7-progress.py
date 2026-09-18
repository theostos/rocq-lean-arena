#!/usr/bin/env python3
"""Validate the Etale projection-order release and resume the sealed 30M generation.

No producer artifact, seal, checking policy, or checkpoint interval is changed.
The validation batch must have completed before this separate launch step.
"""
import argparse
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

ALIGN = HERE.parent / 'kernel-alignment-pass'
CHAR = HERE.parent / 'mathlib-char-succ-repro'
OLDCHAR = HERE.parent / 'mathlib-char-ordinal-repro'
RIEM = HERE.parent / 'mathlib-riemann-sharing-repro'
LIE = HERE.parent / 'mathlib-lie-trace-repro'
GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
GATES = ALIGN / 'final-gates-etale-v7'
CONSUMER = ALIGN / 'importer.eZWQ15ef'
COMPLETED = json.loads((HERE / 'validation-etale-v7-progress/passed.json').read_text())
WORKER_SHA = COMPLETED['worker_sha256']
CHECKER_SHA = COMPLETED['checker_sha256']
UNIT = 'rocq-mathlib-alignment-5m-etale-v7.service'
RELEASE = HERE.parent / 'mathlib-etale-release-20260916-v7'


def require(condition, message):
    if not condition:
        raise chunks.Refused(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate-only', action='store_true')
    args = parser.parse_args()
    certificate_path = HERE / 'consumer-certificate-etale-v7.json'
    approval_path = HERE / 'resume-approval-etale-v7.json'
    require(not certificate_path.exists() and not approval_path.exists(),
            'An approval already exists; inspect the run before trying again')
    require(not RELEASE.exists(), 'The immutable release directory already exists')
    require(not (GENERATION / 'PAUSE').exists(), 'A pause request is present')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__))}
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
        for field in ('inputs', 'source_inputs', 'consumer_importer_inputs', 'outputs', 'completion_inputs'):
            if field in record:
                add(record[field])
        add({str(path): chunks.sha(path)})
        evidence[str(path)] = record
        return record

    def replay(directory, current=True):
        record = read(directory / 'result.json', current=current)
        add({str(directory / (record['module'] + '.vo')): record['vo_sha256']})
        if current:
            read(directory / 'invocation.json')
        return record

    batch = read(HERE / 'validation-etale-v7-progress/passed.json')
    expected = ['gates', 'native-independent', 'strict-native-independent', 'strict-policy',
                'etale-independent', 'original-order', 'original-independent',
                'riemannian', 'riemannian-independent', 'recursive-alias', 'previous-char',
                'combined-char', 'combined-independent', 'sset', 'sset-independent',
                'lie', 'lie-independent', 'derivative', 'derivative-independent']
    require(batch['consumer'] == str(CONSUMER) and batch['tag'] == 'etale-v7'
            and batch['slice'] == str(HERE / 'candidate-slice-v7')
            and batch['max_memory_mib'] == 16384 and batch['reserve_mib'] == 3072,
            'Unexpected qualification candidate, slice, or resource policy')
    require(batch['checker_sha256'] == CHECKER_SHA
            and [r['label'] for r in batch['results']] == expected
            and all(r['exit_code'] == 0 for r in batch['results']),
            'The complete serial validation batch has not passed')
    require(batch['reused_stages'] == 6 and batch['reused_validation'] ==
            str(HERE / 'validation-etale-v7'), 'Unexpected reused evidence')
    deadline_tests = read(HERE / 'deadline-tests.json')
    require(deadline_tests['tests'] >= 215 and deadline_tests['skipped'] <= 2,
            'Deadline and runner tests incomplete')
    gate = read(GATES / 'passed.json')
    require(gate['native_fixtures'] == 19 and gate['legacy_fixtures'] == 20
            and {'typeops_application_conversions', 'checker_typed_conversion',
                 'private_demand_sharing', 'private_type_query',
                 'projection_congruence_segments', 'projection_argument_order',
                 'projection_mismatched_fields', 'lazy_projection_sources'}
                <= set(gate['runtime_unit_families']), 'Incomplete regression gate')
    legacy = read(GATES / 'legacy-regressions/passed.json')
    require(legacy['tests'] == 20 and len(legacy['results']) == 20
            and all(r['exit_code'] == 0 for r in legacy['results']),
            'Incomplete legacy regression evidence')
    runner = read(GATES / 'runner-tests.json')
    require(runner['tests'] >= 206 and runner['skipped'] <= 2,
            'Incomplete runner/resource/checkpoint tests')
    require(read(GATES / 'importer-regressions/passed.json')['tests'] == 44,
            'Incomplete importer regressions')
    read(GATES / 'fresh-smoke/result.json')
    ordinary = read(GATES / 'independent-check.json')
    require(ordinary['native_fixtures'] == 19 and not ordinary['admitted_dependencies'],
            'Incomplete independent native checking')
    strict = read(GATES / 'strict-independent-check.json')
    require(strict['strict_theory_profile'] and strict['strict_profile']['allow_definitional_uip']
            and strict['native_fixtures'] == 19 and not strict['admitted_dependencies'],
            'Incomplete strict native checking')
    policy = read(ALIGN / 'strict-checker-etale-v7/passed.json')
    require(len(policy['checks']) == 11, 'Incomplete strict-checker policy gate')

    manifest = read(HERE / 'slice.json')
    require(manifest['keep_all_proofs'] and manifest['stats']['abstracted'] == 0,
            'Etale dependency proofs were abstracted')
    require(replay(HERE / 'candidate-slice-v7')['module'] == 'EtaleWhole',
            'Wrong Etale dependency replay')
    etale_check = read(HERE / 'candidate-slice-v7/independent.json')
    require(etale_check['range'] == [1, 3140945]
            and etale_check['admitted_dependencies'] and not etale_check['strict'],
            'Incomplete independent Etale slice checking')

    manifest = read(CHAR / 'slice.json')
    require(manifest['keep_all_proofs'] and manifest['stats']['abstracted'] == 0,
            'Char dependency proofs were abstracted')
    replay(OLDCHAR / 'prefix', current=False)
    replay(OLDCHAR / 'target-etale-v7')
    alias = read(HERE / 'alias-etale-v7/result.json')
    read(HERE / 'alias-etale-v7/invocation.json')
    add({str(HERE / 'alias-etale-v7/FixPriority.vo'): alias['vo_sha256']})
    require(replay(HERE / 'original-etale-v7')['module'] == 'MathlibTo35000000',
            'Wrong uninterrupted original-order Etale replay')
    checked = read(HERE / 'original-etale-v7/independent-progress.json')
    require(checked['deadline_policy'] == {
        'kind': 'declaration-progress', 'seconds': 1800,
        'startup_and_finalization_bounded': True, 'resets_on': 'target-constant-start-only'},
        'Unexpected checker deadline policy')
    require(checked['progress']['phase'] == 'passed' and checked['progress']['exit_code'] == 0
            and checked['progress']['module'] == 'MathlibTo35000000'
            and checked['progress']['declarations_started'] > 0,
            'Incomplete progress-aware independent checking')
    require(checked['range'] == [30000001, 31651933]
            and checked['admitted_dependencies'] and not checked['strict'],
            'Incomplete independent Etale segment checking')
    require(replay(CHAR / 'whole-etale-v7')['module'] == 'CharWhole', 'Wrong Char replay')
    independent = read(CHAR / 'whole-etale-v7/independent.json')
    require(independent['admitted_dependencies'] and not independent['strict'],
            'Unexpected Char independent-checking scope')
    controls = read(LIE / 'proof-etale-v7/diagnostic-controls.json')
    require(not controls['environment'], 'A diagnostic conversion policy was enabled')
    for base, prefix, target, name in (
            (LIE, 'proof-prefix', 'proof-etale-v7', 'slice.json'),
            (RIEM, 'sset-prefix', 'sset-etale-v7', 'sset-slice.json'),
            (RIEM, 'derivative-prefix', 'derivative-etale-v7', 'derivative-slice.json')):
        manifest = read(base / name)
        require(manifest['keep_all_proofs'], 'Dependency proofs were abstracted')
        if base != LIE:
            require(manifest['stats']['abstracted'] == 0, 'Sub-slice contains abstracted proofs')
        replay(base / prefix, current=False)
        replay(base / target)
        independent = read(base / target / 'independent-target.json')
        require(independent['admitted_dependencies'] and not independent['strict'],
                'Unexpected independent continuation scope')
    original = RIEM / 'riemannian-etale-v7'
    require(replay(original)['module'] == 'RiemannianWholeFrom25M',
            'Wrong original-order replay')
    independent = read(original / 'independent-original-order.json')
    require(independent['range'] == [25000001, 25525775]
            and independent['admitted_dependencies'] and not independent['strict'],
            'Incomplete original-order continuation checking')

    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    require(chunks.sha(plan_path) == '31b67da20277d497f23d2ca44c4a605dd11f47a914fb218caf09cb02cea34e7d',
            'Production plan changed')
    add(chunks.generation_toolchain(plan)['inputs'])
    add({str(plan_path): chunks.sha(plan_path)})
    cursor = plan_path.parent / 'progress.json'
    progress = json.loads(cursor.read_text())
    require(progress['module'] == 'MathlibTo30000000' and progress['next_line'] == 30000001
            and progress['artifact_sha256'] ==
            '5876870f3b1c07bc8299ad8f44364a84f6e6837b24fe376b16cced69e04c79d0'
            and progress['reload_sha256'] ==
            '89079615bfcc92a4cf89135626f63050bb697e6abd5085aad32dd220f0cee6e6',
            'Saved production cursor changed')
    require(plan['interval'] == 5000000 and plan['line_timeout'] == 1800
            and plan['memory_mib'] == 16384, 'Production limits changed')
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo30000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'],
                           stdout=subprocess.DEVNULL).returncode == 1,
            'A worker is still running')
    for unit in (UNIT, 'rocq-mathlib-alignment-5m-char-succ.service',
                 'rocq-mathlib-alignment-5m-char-eliminator.service',
                 'rocq-mathlib-alignment-5m-two-view.service',
                 'rocq-mathlib-alignment-5m-lie-sharing.service',
                 'rocq-mathlib-alignment-5m-except-conds.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'A production service is already running: ' + unit)
    if args.validate_only:
        print('All promotion checks passed; no files written and no service started.', flush=True)
        return

    # Freeze completed validation and the adapter. Runtime inputs stay checked;
    # future worktree source edits do not retroactively rewrite producer seals.
    RELEASE.mkdir()
    source_adapter = ALIGN / 'consumer_toolchain.py'
    adapter_path = RELEASE / 'consumer_toolchain.py'
    shutil.copy2(source_adapter, adapter_path)
    require(chunks.sha(adapter_path) == inputs[str(source_adapter)],
            'Frozen adapter differs from the validated source')
    receipt_path = RELEASE / 'validation-receipt.json'
    chunks.save_json(receipt_path, {
        'format': 'rocq-completed-validation-v1', 'worker_sha256': WORKER_SHA,
        'checker_sha256': CHECKER_SHA, 'validated_inputs': inputs, 'evidence': evidence,
        'scope': 'Completed checks on these versions, not live worktree dependencies',
        'dependency_scope': 'Every Etale/Char slice proof, original 30M-to-Etale segment and19 native fixtures rechecked; sealed Mathlib prefixes reused'})
    spec = importlib.util.spec_from_file_location('consumer_toolchain', adapter_path)
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    certificate = adapter.make_certificate(plan_path, CONSUMER,
        {str(receipt_path): chunks.sha(receipt_path)})
    require(certificate['worker_sha256'] == WORKER_SHA and all(
        path not in inputs or inputs[path] == digest for path, digest in certificate['inputs'].items()),
        'Runtime inputs changed after validation')
    chunks.save_json(certificate_path, certificate)
    certificate_hash = chunks.sha(certificate_path)
    with adapter.installed_consumer(certificate_path, certificate_hash):
        require(chunks.generation_toolchain(plan)['importer'] == str(CONSUMER),
                'Consumer profile was not installed')
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(adapter_path), '--certificate', str(certificate_path),
        '--sha256', certificate_hash]
    chunks.save_json(approval_path, {
        'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 30000001, 'service': UNIT, 'command': command,
        'certificate': str(certificate_path), 'certificate_sha256': certificate_hash,
        'validation_receipt': str(receipt_path), 'inputs': inputs, 'notes': [
            'Producer artifacts and seals remain unchanged.',
            'Importer source unchanged; plugin rebuilt only for the kernel ABI.',
            'Existing launcher verifies and reloads the sealed 30M dependency chain.',
            'Checking flags, 5M interval, 1800s declaration limit and 16GiB/no-swap guard unchanged.',
            'Full Mathlib verification remains incomplete until EOF.',
            'No assistant monitoring after the startup check.']})
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming from line 30,000,001:', GENERATION, flush=True)


if __name__ == '__main__':
    main()
