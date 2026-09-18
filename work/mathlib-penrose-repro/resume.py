#!/usr/bin/env python3
"""Qualify the Penrose repair and resume the immutable 55M checkpoint chain."""
import argparse
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
CONSUMER = HERE.parent / 'kernel-alignment-pass/importer.m63OyviU'
ADAPTER = HERE.parent / 'mathlib-srg-release-20260917-v1/consumer_toolchain.py'
MEMORY = HERE.parent / 'mathlib-cotangent-repro/resume-25gb.py'
WORKER_SHA = 'a0aa7234b01883d29dcc51bc6b99e14065df4aa9dbff3d194e225f5fb1757983'
CHECKER_SHA = '769c3beaaa291ecb2985117c154cb5f437192a9c74212c74d9f9e1cdc310341e'
BASELINE = 'd17b66af824e344393b126e57fbcec99174f926a'
UNIT = 'rocq-mathlib-penrose-25gb.service'
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
    require(not any(p.exists() for p in (RECEIPT, CERTIFICATE, APPROVAL)), 'Release already exists')
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
    slice_record = read(HERE / 'slice.json')
    require(slice_record['original_line'] == 58521284 and slice_record['keep_all_proofs']
            and slice_record['stats']['abstracted'] == 0, 'Wrong extraction scope')
    legacy = read(HERE / 'legacy.json')
    require(legacy['range'] == {'start': 9939, 'end': 9940}, 'Wrong replay range')
    prefix = read(HERE / 'baseline-prefix-legacy/result.json', historical=True)
    require(prefix['module'] == 'PenrosePrefixLegacy', 'Wrong prefix')
    add({str(HERE / 'baseline-prefix-legacy/PenrosePrefixLegacy.vo'): prefix['vo_sha256']})
    for base, module in ((HERE / 'candidate-target-7', 'PenroseTargetLegacy'),
                         (HERE.parent / 'mathlib-padic-repro/penrose-regression-2', 'PadicTarget')):
        result = read(base / 'result.json')
        require(result['module'] == module and result['worker_sha256'] == WORKER_SHA,
                'Wrong replay worker/module')
        add({str(base / (module + '.vo')): result['vo_sha256']})
        invocation = read(base / 'invocation.json')
        require(str(CONSUMER / 'src') in invocation['command'], 'Wrong importer')
    standalone = read(HERE / 'candidate-target-7/standalone-evidence.json')
    independent = read(Path(standalone['evidence']))
    require(standalone['artifact_sha256'] ==
            chunks.sha(HERE / 'candidate-target-7/PenroseTargetLegacy.vo'), 'Standalone artifact mismatch')
    checked_artifacts = [digest for path, digest in independent['inputs'].items()
                         if path.endswith('/PenroseTargetLegacy.vo')]
    require(checked_artifacts == [standalone['artifact_sha256']], 'Different artifact checked')
    require(independent['admitted_dependencies'] and not independent['strict']
            and independent['progress']['phase'] == 'passed', 'Wrong independent scope')
    focused = read(HERE / 'candidate-focused-2/result.json')
    require(focused['worker_sha256'] == WORKER_SHA and len(focused['fixtures']) == 18
            and all(t['exit_code'] == 0 for t in focused['fixtures']), 'Incomplete focused tests')
    units = read(HERE / 'candidate-units-3/result.json')
    require(units['worker_sha256'] == WORKER_SHA and len(units['tests']) == 10
            and all(t['exit_code'] == 0 for t in units['tests']), 'Incomplete native tests')
    for path in (Path(__file__), ADAPTER, MEMORY, HERE / 'README.md'):
        add({str(path): chunks.sha(path)})
    source_diff = subprocess.check_output(['git', 'diff', BASELINE, '--', 'kernel', 'checker'],
                                         cwd=chunks.KERNEL, text=True)
    changed = subprocess.check_output(['git', 'diff', '--name-only', BASELINE, '--', 'kernel', 'checker'],
                                     cwd=chunks.KERNEL, text=True).splitlines()
    require(set(changed) == {'kernel/constr.ml', 'kernel/hConstr.ml',
                            'kernel/typeops.ml', 'kernel/vars.ml', 'checker/validate.ml',
                            'checker/mod_checking.ml'},
            'Unexpected kernel/checker changes')
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    require(chunks.sha(plan_path) == '31b67da20277d497f23d2ca44c4a605dd11f47a914fb218caf09cb02cea34e7d'
            and (plan['interval'], plan['line_timeout'], plan['memory_mib']) ==
            (5000000, 1800, 16384), 'Historical plan changed')
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    require(progress['module'] == 'MathlibTo55000000' and progress['next_line'] == 55000001
            and progress['artifact_sha256'] == '73f1db317d8e41388b6f115efa9be34cb1f98d72be946034557125b6987e9f67'
            and progress['reload_sha256'] == '77ee0411986b2bb2a186aec9c1fc063e073b8975e98541c237d93d05fcfbe260',
            '55M cursor changed')
    last = next(c for c in plan['chunks'] if c['module'] == progress['module'])
    require(chunks.verify_saved(plan_path.parent, last) is not None, 'Invalid 55M seal')
    add(chunks.generation_toolchain(plan)['inputs'])
    add({str(plan_path): chunks.sha(plan_path)})
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo55000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'], stdout=subprocess.DEVNULL).returncode == 1,
            'Worker running')
    for unit in (UNIT, 'rocq-mathlib-padic-25gb.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'Production service running')
    chunks.save_json(RECEIPT, dict(
        format='rocq-completed-validation-v1', worker_sha256=WORKER_SHA, checker_sha256=CHECKER_SHA,
        validated_inputs=inputs, evidence=evidence, source_diff=source_diff,
        scope='Exact Penrose proof, standalone target check, prior Padic failure, 18 focused fixtures and 10 native test groups',
        dependency_scope='All Penrose dependency proofs retained and compiled; standalone checker reuses prefix/foundation; sealed 0–55M checkpoints reused',
        full_mathlib_pass=False, full_regression_suite=False))
    adapter = load('penrose_consumer', ADAPTER)
    certificate = adapter.make_certificate(plan_path, CONSUMER, {str(RECEIPT): chunks.sha(RECEIPT)})
    require(certificate['worker_sha256'] == WORKER_SHA, 'Worker changed')
    chunks.save_json(CERTIFICATE, certificate)
    certificate_sha = chunks.sha(CERTIFICATE)
    with adapter.installed_consumer(CERTIFICATE, certificate_sha):
        runtime = dict(chunks.generation_toolchain(plan)['inputs'])
    runtime.update({str(p): chunks.sha(p) for p in (Path(__file__), MEMORY, ADAPTER, plan_path)})
    chunks.save_json(APPROVAL, dict(
        format='rocq-runtime-memory-override-v1', inputs=runtime, worker_sha256=WORKER_SHA,
        plan=str(plan_path), resume_from=55000001, unit=UNIT, certificate=str(CERTIFICATE),
        certificate_sha256=certificate_sha, requested_max_bytes=25_000_000_000,
        memory_max_kib=24414062, rss_max_kib=24414062, reserve_kib=2097152, swap_max_kib=0,
        historical_plan_memory_mib=16384,
        notes=['Same serial proof policy, 1800s line timeout, 5M interval, 25GB cap, 2GiB reserve.',
               'No skipped proofs, altered producer seals, deleted checkpoints or remote changes.']))
    digest = chunks.sha(APPROVAL)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(['systemd-run', '--user', '--unit=' + UNIT, '--collect', '--property=Restart=no',
        '--working-directory=' + str(ROOT), '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + WORKER_SHA,
        '/usr/bin/python3', str(Path(__file__)), 'run', '--approval-sha256', digest], env=env, check=True)
    print('Started continuation from 55,000,001; approval SHA256:', digest, flush=True)

def run(digest):
    require(digest and chunks.sha(APPROVAL) == digest, 'Approval changed')
    policy = json.loads(APPROVAL.read_text())
    require(policy['certificate'] == str(CERTIFICATE) and policy['unit'] == UNIT
            and policy['resume_from'] == 55000001 and policy['reserve_kib'] == 2097152,
            'Unexpected continuation')
    chunks.check_entries(policy['inputs'])
    memory = load('penrose_memory', MEMORY)
    memory.APPROVAL, memory.CERTIFICATE = APPROVAL, CERTIFICATE
    memory.CERTIFICATE_SHA, memory.UNIT = policy['certificate_sha256'], UNIT
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
