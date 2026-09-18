#!/usr/bin/env python3
"""Explicit runtime-only memory migration; historical plans/seals stay immutable."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import types

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import mathlib_ndjson_loop as loop

GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
CERTIFICATE = HERE / 'consumer-certificate.json'
CERTIFICATE_SHA = 'cc5567c8541eca58c3dcef6d096c9029f436e31bb7dd75e483936212e2c9b0ed'
ADAPTER = HERE.parent / 'mathlib-srg-release-20260917-v1/consumer_toolchain.py'
UNIT = 'rocq-mathlib-cotangent-25gb.service'
LIMIT_KIB = 25_000_000_000 // 1024  # Decimal GB; round down, never exceed request.
APPROVAL = HERE / 'memory-25gb-approval.json'


def require(condition, message):
    if not condition:
        raise chunks.Refused(message)


def load_adapter():
    spec = importlib.util.spec_from_file_location('cotangent_consumer', ADAPTER)
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    return adapter


def resource_environment(env, reserve_kib):
    require(env['ROCQ_MEMORY_MAX_KIB'] == '16777216'
            and env['ROCQ_MEMORY_HIGH_KIB'] == '16777216'
            and env['ROCQ_MAX_RSS_KIB'] == '15728640'
            and env['ROCQ_MIN_AVAILABLE_KIB'] == '3145728'
            and env['ROCQ_MEMORY_SWAP_MAX_KIB'] == '0',
            'Unexpected original resource policy')
    require(reserve_kib in (2048 * 1024, 3072 * 1024), 'Unsupported host reserve')
    return dict(env, ROCQ_MAX_RSS_KIB=str(LIMIT_KIB),
                ROCQ_MEMORY_MAX_KIB=str(LIMIT_KIB), ROCQ_MEMORY_HIGH_KIB=str(LIMIT_KIB),
                ROCQ_MIN_AVAILABLE_KIB=str(reserve_kib))


def memory_compiler(original, reserve_kib, run_process=subprocess.run):
    # Reuse the exact sealed compiler function and command construction. Give
    # only this call a private subprocess namespace; do not alter the shared
    # subprocess module (the progress reporter runs in another thread).
    class Process:
        STDOUT = subprocess.STDOUT

        @staticmethod
        def run(*args, **kwargs):
            return run_process(*args, **dict(kwargs,
                env=resource_environment(kwargs['env'], reserve_kib)))

    def compile_module(*args, **kwargs):
        local = types.FunctionType(original.__code__,
            dict(original.__globals__, subprocess=Process), original.__name__,
            original.__defaults__, original.__closure__)
        local.__kwdefaults__ = original.__kwdefaults__
        return local(*args, **kwargs)
    return compile_module


def approve(reserve_mib):
    require(not APPROVAL.exists(), 'Approval already exists; do not overwrite it')
    require(not (GENERATION / 'PAUSE').exists(), 'Pause requested')
    require(subprocess.run(['pgrep', '-x', 'rocqworker.*'],
                           stdout=subprocess.DEVNULL).returncode == 1, 'Worker already running')
    adapter = load_adapter()
    with adapter.installed_consumer(CERTIFICATE, CERTIFICATE_SHA) as (plan_path, plan):
        require((plan['interval'], plan['line_timeout'], plan['memory_mib']) ==
                (5000000, 1800, 16384), 'Historical plan changed')
        progress = json.loads((plan_path.parent / 'progress.json').read_text())
        require(progress['module'] == 'MathlibTo45000000' and progress['next_line'] == 45000001,
                'Resume cursor is not 45M')
        last = next(c for c in plan['chunks'] if c['module'] == progress['module'])
        require(chunks.verify_saved(plan_path.parent, last) is not None, 'Invalid 45M checkpoint')
        chunks.check_disk(GENERATION, plan_path.parent / 'MathlibTo45000000.vo')
        profile = chunks.generation_toolchain(plan)
        inputs = dict(profile['inputs'])
        inputs.update({str(p): chunks.sha(p) for p in
                       (Path(__file__), plan_path, CERTIFICATE, ADAPTER)})
        chunks.save_json(APPROVAL, {
            'format': 'rocq-runtime-memory-override-v1', 'inputs': inputs,
            'worker_sha256': profile['worker_sha256'], 'plan': str(plan_path),
            'resume_from': 45000001, 'unit': UNIT,
            'requested_max_bytes': 25_000_000_000, 'memory_max_kib': LIMIT_KIB,
            'rss_max_kib': LIMIT_KIB, 'reserve_kib': reserve_mib * 1024, 'swap_max_kib': 0,
            'historical_plan_memory_mib': 16384,
            'note': 'User-authorized memory increase only; proof policy, binaries, checkpoint interval and producer seals unchanged.'})
    digest = chunks.sha(APPROVAL)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('ROCQ_', '_ROCQ_', 'LEAN_IMPORT_', 'ROCQLKA_'))}
    command = ['systemd-run', '--user', '--unit=' + UNIT, '--collect',
        '--property=Restart=no', '--working-directory=' + str(ROOT),
        '--setenv=ROCQ_MEMORY_OWNER_SERVICE=' + UNIT,
        '--setenv=ROCQ_APPROVED_WORKER_SHA256=' + profile['worker_sha256'],
        '/usr/bin/python3', str(Path(__file__)), 'run', '--approval-sha256', digest]
    subprocess.run(command, env=env, check=True)
    print('Started 25 GB continuation from 45M; approval SHA256:', digest, flush=True)


def run(digest):
    require(chunks.sha(APPROVAL) == digest, 'Memory approval changed')
    policy = json.loads(APPROVAL.read_text())
    require(policy['format'] == 'rocq-runtime-memory-override-v1'
            and policy['memory_max_kib'] == LIMIT_KIB and policy['rss_max_kib'] == LIMIT_KIB
            and policy['swap_max_kib'] == 0, 'Unexpected approved memory policy')
    require(not any(k.startswith(('ROCQ_DIAGNOSTIC_', 'ROCQ_EXPERIMENTAL_', 'LEAN_IMPORT_'))
                    for k in os.environ), 'Diagnostic overrides present')
    chunks.check_entries(policy['inputs'])
    adapter = load_adapter()
    with adapter.installed_consumer(CERTIFICATE, CERTIFICATE_SHA) as (plan_path, plan):
        require(str(plan_path) == policy['plan'], 'Different plan requested')
        original_loader = chunks.generation_toolchain
        original_compiler = chunks.compile_module
        original_importer = loop.direct.checking.IMPORTER

        def loader(requested):
            profile = original_loader(requested)
            chunks.check_entries(policy['inputs'])
            require(chunks.sha(APPROVAL) == digest, 'Memory approval changed')
            inputs = dict(profile['inputs'])
            for name, sha in policy['inputs'].items():
                require(name not in inputs or inputs[name] == sha, 'Conflicting runtime input')
                inputs[name] = sha
            inputs[str(APPROVAL)] = digest
            return dict(profile, inputs=inputs, runtime_memory_policy=str(APPROVAL))

        chunks.generation_toolchain = loader
        chunks.compile_module = memory_compiler(original_compiler, policy['reserve_kib'])
        loop.direct.checking.IMPORTER = Path(loader(plan)['importer'])
        try:
            print('Runtime policy: 25 GB hard/RSS cap, reserve %d MiB, no swap; original proof policy.'
                  % (policy['reserve_kib'] // 1024), flush=True)
            return loop.run(GENERATION, False, plan['memory_mib'], plan['interval'], plan['line_timeout'])
        finally:
            loop.direct.checking.IMPORTER = original_importer
            chunks.compile_module = original_compiler
            chunks.generation_toolchain = original_loader


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['approve', 'run'])
    parser.add_argument('--reserve-mib', type=int, choices=[2048, 3072], default=3072)
    parser.add_argument('--approval-sha256')
    args = parser.parse_args()
    if args.command == 'approve':
        approve(args.reserve_mib)
        return 0
    require(args.approval_sha256 is not None, 'Missing approval hash')
    return run(args.approval_sha256)


if __name__ == '__main__':
    raise SystemExit(main())
