#!/usr/bin/env python3
"""Resume the sealed 40M generation with the exact constructor-context fix.

The user explicitly waived broader regressions. The complete proof-preserving
SRG slice and its independent recheck passed; the kernel binary is unchanged.
"""
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
RELEASE = HERE.parent / 'mathlib-srg-release-20260917-v1'
CONSUMER = HERE.parent / 'kernel-alignment-pass/importer.q64CBLVp'
BASELINE = HERE.parent / 'kernel-alignment-pass/importer.KxXeEAdv'
WORKER_SHA = 'a363c589e05023fecfe27114ef587aeeb88715717929eafedbd3dece21c00b36'
CHECKER_SHA = '914d4a35b2156c0e584837010cc519b6281d8847f2d33beec31f303a85db2a0b'
UNIT = 'rocq-mathlib-alignment-5m-srg-v1.service'

def require(condition, message):
    if not condition:
        raise chunks.Refused(message)

def main():
    receipt_path = RELEASE / 'validation-receipt.json'
    certificate_path = HERE / 'consumer-certificate.json'
    approval_path = HERE / 'resume-approval.json'
    require(not any(p.exists() for p in (receipt_path, certificate_path, approval_path)),
            'A release already exists; inspect it before retrying')
    require(not (GENERATION / 'PAUSE').exists(), 'A pause request is present')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(chunks.WORKER): WORKER_SHA, str(checker): CHECKER_SHA,
              str(Path(__file__)): chunks.sha(Path(__file__))}
    evidence = {}
    def add(entries):
        for path, digest in entries.items():
            require(path not in inputs or inputs[path] == digest, 'Conflicting input: ' + path)
            inputs[path] = digest
    def read(path):
        record = json.loads(path.read_text())
        require(record.get('exit_code', 0) == 0, 'Failed evidence: ' + str(path))
        for field in ('inputs', 'outputs'):
            add(record.get(field, {}))
        add({str(path): chunks.sha(path)})
        evidence[str(path)] = record
        return record
    manifest = read(HERE / 'slice.json')
    require(manifest['keep_all_proofs'] and manifest['stats']['abstracted'] == 0,
            'Dependency proofs were abstracted')
    result = read(HERE / 'candidate-slice/result.json')
    require(result['worker_sha256'] == WORKER_SHA and result['module'] == 'SrgWhole',
            'Different worker/module used for validation')
    add({str(HERE / 'candidate-slice/SrgWhole.vo'): result['vo_sha256']})
    invocation = read(HERE / 'candidate-slice/invocation.json')
    require(str(CONSUMER / 'src') in invocation['command'], 'Different importer validated')
    independent = read(HERE / 'candidate-slice/independent.json')
    require(independent['range'] == [1, 61339] and independent['admitted_dependencies']
            and not independent['strict'], 'Unexpected independent-check scope')
    require(chunks.sha(BASELINE / 'src/lean.ml') ==
            '665383b4f65435ede188cc237eb3a07dc92700e3fe0917d7cd0efe60d622c7d2',
            'Baseline importer changed')
    diff = ''.join(difflib.unified_diff(
        (BASELINE / 'src/lean.ml').read_text().splitlines(keepends=True),
        (CONSUMER / 'src/lean.ml').read_text().splitlines(keepends=True),
        fromfile='validated-v9/src/lean.ml', tofile='constructor-context/src/lean.ml'))
    require(diff.count('@@') == 2, 'Expected one localized importer change')
    plan_path = GENERATION / 'checkpoints/plan.json'
    plan = chunks.load_plan(plan_path)
    require(chunks.sha(plan_path) ==
            '31b67da20277d497f23d2ca44c4a605dd11f47a914fb218caf09cb02cea34e7d',
            'Production plan changed')
    require((plan['interval'], plan['line_timeout'], plan['memory_mib']) ==
            (5000000, 1800, 16384), 'Production limits changed')
    progress = json.loads((plan_path.parent / 'progress.json').read_text())
    require(progress['next_line'] == 40000001 and progress['module'] == 'MathlibTo40000000'
            and progress['artifact_sha256'] ==
            '28e625d7257ce2ecb0094584b32edced9330d031eaf0997d73e4e9aaeddc27db'
            and progress['reload_sha256'] ==
            '5c3bd645e212f8453d3094ece49208c0567f94088c6c4e27a61e9d371e4df107',
            'Saved production cursor changed')
    predecessors = [c for c in plan['chunks'] if c['end'] <= 40000001]
    require(len(predecessors) == 8 and predecessors[-1]['end'] == 40000001,
            'Incomplete checkpoint chain')
    for chunk in predecessors:
        require(chunks.verify_saved(plan_path.parent, chunk) is not None,
                'Invalid checkpoint: ' + chunk['module'])
    add(chunks.generation_toolchain(plan)['inputs'])
    add({str(plan_path): chunks.sha(plan_path)})
    chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo40000000.vo')
    chunks.check_entries(inputs)
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'],
                           stdout=subprocess.DEVNULL).returncode == 1, 'A worker is running')
    for unit in (UNIT, 'rocq-mathlib-alignment-5m-etale-v9.service'):
        require(subprocess.run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode != 0,
                'Production service already running: ' + unit)
    adapter_path = RELEASE / 'consumer_toolchain.py'
    add({str(adapter_path): chunks.sha(adapter_path)})
    chunks.save_json(receipt_path, {
        'format': 'rocq-completed-validation-v1', 'worker_sha256': WORKER_SHA,
        'checker_sha256': CHECKER_SHA, 'validated_inputs': inputs, 'evidence': evidence,
        'source_diff': diff, 'broader_regressions': 'Explicitly waived by the user',
        'scope': 'Complete SRG dependency slice and independent recheck passed; kernel unchanged',
        'dependency_scope': 'Foundation/stdlib reused; sealed 0–40M ancestors reused',
        'full_mathlib_pass': False})
    spec = importlib.util.spec_from_file_location('srg_consumer', adapter_path)
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
        '/usr/bin/python3', str(adapter_path), '--certificate', str(certificate_path),
        '--sha256', certificate_hash]
    chunks.save_json(approval_path, {
        'worker_sha256': WORKER_SHA, 'checker_sha256': CHECKER_SHA,
        'resume_from': 40000001, 'service': UNIT, 'command': command,
        'certificate': str(certificate_path), 'certificate_sha256': certificate_hash,
        'validation_receipt': str(receipt_path), 'inputs': inputs,
        'notes': ['Broader regressions skipped at explicit user request.',
                  'Producer checkpoints and all checking/resource limits unchanged.',
                  'Only the reviewed constructor-context importer fix is authorized.',
                  'No assistant monitoring after the startup check.']})
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    subprocess.run(command, check=True, env=env)
    print('Resuming from line 40,000,001:', GENERATION, flush=True)

if __name__ == '__main__':
    main()
