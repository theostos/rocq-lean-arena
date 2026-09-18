#!/usr/bin/env python3
"""Release the focused Padic cast-conversion repair and resume the sealed 50M generation."""
import argparse
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
CONSUMER = HERE.parent / 'kernel-alignment-pass/importer.rEXkanSl'
ADAPTER = HERE.parent / 'mathlib-srg-release-20260917-v1/consumer_toolchain.py'
MEMORY = HERE.parent / 'mathlib-cotangent-repro/resume-25gb.py'
WORKER_SHA = '484cb306cb0f5d114071d601202a45c93de9c7ee803bbcd5c455553a6863649a'
CHECKER_SHA = '03fc74e26566f707a62042d1147243b41f0555371795dc2ef30c582be7c68181'
UNIT = 'rocq-mathlib-padic-25gb.service'
RECEIPT = HERE / 'validation-receipt.json'
CERTIFICATE = HERE / 'consumer-certificate.json'
APPROVAL = HERE / 'resume-approval.json'


def require(condition, message):
    if not condition:
        raise chunks.Refused(message)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def release():
    require(not any(p.exists() for p in (RECEIPT, CERTIFICATE, APPROVAL)),
            'Release already exists; inspect it before retrying')
    require(not (GENERATION / 'PAUSE').exists(), 'Pause requested')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA}
    evidence = {}

    def add(entries):
        for path, digest in entries.items():
            require(path not in inputs or inputs[path] == digest, 'Conflicting input: ' + path)
            inputs[path] = digest

    def read(path, historical=False):
        record = json.loads(path.read_text())
        require(record.get('exit_code', 0) == 0, 'Failed validation: ' + str(path))
        if not historical:
            for field in ('inputs', 'outputs'):
                add(record.get(field, {}))
        add({str(path): chunks.sha(path)})
        evidence[str(path)] = record
        return record

    replay = read(HERE / 'slice.json')
    require(replay['original_line'] == 54302445 and replay['keep_all_proofs']
            and replay['stats']['abstracted'] == 0
            and replay['range'] == {'start': 2636964, 'end': 2636965},
            'Unexpected extraction/target')
    prefix = read(HERE / 'baseline-prefix/result.json', historical=True)
    require(prefix['module'] == 'PadicPrefix', 'Wrong dependency prefix')
    add({str(HERE / 'baseline-prefix/PadicPrefix.vo'): prefix['vo_sha256']})
    for directory, module in (('candidate-target', 'PadicTarget'),):
        base = HERE / directory
        result = read(base / 'result.json')
        require(result['module'] == module and result['worker_sha256'] == WORKER_SHA,
                'Different worker/module validated')
        add({str(base / (module + '.vo')): result['vo_sha256']})
        invocation = read(base / 'invocation.json')
        require(str(CONSUMER / 'src') in invocation['command'], 'Different importer validated')
    independent = read(HERE / 'candidate-target/independent-retry.json')
    require(independent['admitted_dependencies'] and not independent['strict']
            and independent['progress']['phase'] == 'passed', 'Unexpected independent scope')
    for directory in ('baseline-target-trace',):
        path = HERE / directory / 'result.json'
        baseline_result = json.loads(path.read_text())
        require(baseline_result['exit_code'] == 1, 'Missing reproduced baseline failure')
        add({str(path): chunks.sha(path)})
        evidence[str(path)] = baseline_result
    focused = read(HERE / 'candidate-focused/result.json')
    require(focused['worker_sha256'] == WORKER_SHA
            and len(focused['fixtures']) == 16
            and all(f['exit_code'] == 0 for f in focused['fixtures']),
            'Incomplete focused regressions')
    unit_log = HERE / 'inversion-unit-6.log'
    require('inversion control: checked term, inherited work, exhaustion, symbolic deferral and same-cell retry passed'
            in unit_log.read_text() and 'finished with status 0;' in unit_log.read_text(),
            'Missing checked-term unit validation')
    evidence['inversion_unit'] = {
        'log': str(unit_log), 'exit_code': 0,
        'scope': '32 projected-major tests plus checked inversion, shared work, exhaustion and same-cell retry'}
    diff = ''
    for name in ('conversion.ml', 'cClosure.ml', 'cClosure.mli'):
        source = chunks.KERNEL / 'kernel' / name
        baseline = HERE / (Path(name).stem + '-baseline' + Path(name).suffix)
        diff += ''.join(difflib.unified_diff(
            baseline.read_text().splitlines(keepends=True),
            source.read_text().splitlines(keepends=True),
            fromfile='production/kernel/' + name, tofile='padic/kernel/' + name))
        add({str(source): chunks.sha(source), str(baseline): chunks.sha(baseline)})
    require('info_conversion_work infos' in diff and 'not info.i_symbolic' in diff,
            'Missing reviewed cast-conversion repair')
    for path in (Path(__file__), ADAPTER, MEMORY, HERE / 'README.md', unit_log,
                 HERE / 'test-inversion.sh', HERE / 'inversion_control_test.ml',
                 HERE.parent / 'kernel-alignment-pass/projected_major_test.ml'):
        add({str(path): chunks.sha(path)})
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    require(chunks.sha(plan_path) ==
            '31b67da20277d497f23d2ca44c4a605dd11f47a914fb218caf09cb02cea34e7d'
            and (plan['interval'], plan['line_timeout'], plan['memory_mib']) ==
            (5000000, 1800, 16384), 'Historical plan changed')
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    require(progress['module'] == 'MathlibTo50000000' and progress['next_line'] == 50000001
            and progress['artifact_sha256'] ==
            '6eb0364911294dbeca86b26023eb0855f5a62f503ae41f46bcf419d9523a810f'
            and progress['reload_sha256'] ==
            '8f3b1cfc8d8476133a1d58ed89e5a339c94bd737965381c568397cd2faa9e80e',
            'Saved 50M cursor changed')
    last = next(c for c in plan['chunks'] if c['module'] == progress['module'])
    print('Verifying 50M seal; the loop will verify all ancestor seals again.', flush=True)
    require(chunks.verify_saved(plan_path.parent, last) is not None, 'Invalid 50M seal')
    add(chunks.generation_toolchain(plan)['inputs'])
    add({str(plan_path): chunks.sha(plan_path)})
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo50000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'],
                           stdout=subprocess.DEVNULL).returncode == 1, 'Worker running')
    for unit in (UNIT, 'rocq-mathlib-simplex-25gb.service', 'rocq-mathlib-cotangent-25gb.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'Production service already running')
    chunks.save_json(RECEIPT, {
        'format': 'rocq-completed-validation-v1', 'worker_sha256': WORKER_SHA,
        'checker_sha256': CHECKER_SHA, 'validated_inputs': inputs, 'evidence': evidence,
        'source_diff': diff, 'broader_regressions': 'Explicitly waived by the user',
        'scope': 'Exact PadicInt.coe_adicCompletionIntegersEquiv_apply, independent target check, 16 focused fixtures, checked inversion unit',
        'dependency_scope': 'All extracted dependency proofs compiled; prefix, foundation and sealed 0–50M checkpoints reused',
        'full_mathlib_pass': False})
    adapter = load('padic_consumer', ADAPTER)
    certificate = adapter.make_certificate(plan_path, CONSUMER, {str(RECEIPT): chunks.sha(RECEIPT)})
    require(certificate['worker_sha256'] == WORKER_SHA, 'Worker changed')
    chunks.save_json(CERTIFICATE, certificate)
    certificate_sha = chunks.sha(CERTIFICATE)
    with adapter.installed_consumer(CERTIFICATE, certificate_sha):
        runtime_inputs = dict(chunks.generation_toolchain(plan)['inputs'])
    runtime_inputs.update({str(p): chunks.sha(p) for p in (Path(__file__), MEMORY, ADAPTER, plan_path)})
    chunks.save_json(APPROVAL, {
        'format': 'rocq-runtime-memory-override-v1', 'inputs': runtime_inputs,
        'worker_sha256': WORKER_SHA, 'plan': str(plan_path),
        'resume_from': 50000001, 'unit': UNIT,
        'certificate': str(CERTIFICATE), 'certificate_sha256': certificate_sha,
        'requested_max_bytes': 25_000_000_000, 'memory_max_kib': 24414062,
        'rss_max_kib': 24414062, 'reserve_kib': 2097152, 'swap_max_kib': 0,
        'historical_plan_memory_mib': 16384,
        'notes': ['Preserve the previously authorized 25 GB cap and 2 GiB reserve.',
                  'Original serial importer; only ABI rebuilt against the repaired kernel.',
                  'No proof skipping, altered timeouts, checkpoint deletion or full suite.',
                  'No assistant monitoring after startup confirmation.']})
    digest = chunks.sha(APPROVAL)
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(Path(__file__)), 'run', '--approval-sha256', digest]
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, env=env, check=True)
    print('Started continuation from line 50,000,001; approval SHA256:', digest, flush=True)


def run(digest):
    require(digest and chunks.sha(APPROVAL) == digest, 'Approval changed')
    policy = json.loads(APPROVAL.read_text())
    require(policy['certificate'] == str(CERTIFICATE) and policy['unit'] == UNIT
            and policy['resume_from'] == 50000001 and policy['reserve_kib'] == 2097152,
            'Unexpected approved continuation')
    chunks.check_entries(policy['inputs'])
    # Reuse the tested process-local resource adapter, without changing any
    # source or policy already bound into the old 50M producer seal.
    memory = load('padic_memory', MEMORY)
    memory.APPROVAL = APPROVAL
    memory.CERTIFICATE = CERTIFICATE
    memory.CERTIFICATE_SHA = policy['certificate_sha256']
    memory.UNIT = UNIT
    return memory.run(digest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['release', 'run'])
    parser.add_argument('--approval-sha256')
    args = parser.parse_args()
    if args.command == 'release':
        release()
    else:
        raise SystemExit(run(args.approval_sha256))
