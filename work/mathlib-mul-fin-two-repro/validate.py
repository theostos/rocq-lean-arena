#!/usr/bin/env python3
"""Validate erased-proof fallback in original order, then reload and regress."""
import fcntl
from functools import lru_cache
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import run as harness

HERE, ROOT, chunks = harness.HERE, harness.ROOT, harness.chunks


def main():
    stage = Path(tempfile.mkdtemp(prefix='validation-', dir=HERE))
    print('Validation:', stage, flush=True)
    worker_hash = chunks.sha(chunks.WORKER)
    regressions = [chunks.KERNEL / 'test-suite/success' / (name + '.v')
                   for name in ('unit_like_record', 'unit_like_aliases',
                                'projected_constant_congruence', 'congruence_probe_irrelevant')]
    sources = [chunks.KERNEL / 'kernel/conversion.ml',
               chunks.KERNEL / 'kernel/cClosure.ml', *regressions,
               HERE / 'MathlibTo18000000.v', HERE / 'Reload.v',
               HERE / 'run.py', HERE / 'validate.py',
               ROOT / 'work/structured-arrow-repro/validate.py',
               ROOT / 'work/blastadd-unary-repro/validate.py']
    source_hashes = {str(p): chunks.sha(p) for p in sources}

    def replay(name, source, *options):
        print('Starting', name, flush=True)
        with (stage / (name + '.log')).open('x') as log:
            subprocess.run([sys.executable, str(HERE / 'run.py'), str(source),
                            '--directory', str(stage / name), '--wait', *options],
                           cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        print('PASS', name, flush=True)

    for regression in regressions:
        replay(regression.stem, regression, '--native')
    replay('full', HERE / 'MathlibTo18000000.v')
    replay('reload', HERE / 'Reload.v', '--prefix', str(stage / 'full'))

    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if chunks.sha(chunks.WORKER) != worker_hash:
            raise RuntimeError('Worker changed during replay')
        for name, command in (
            ('kernel', [sys.executable, str(ROOT / 'work/structured-arrow-repro/validate.py')]),
            ('importer', [sys.executable, str(ROOT / 'work/blastadd-unary-repro/validate.py'),
                          '--foundation', str(ROOT / 'work/cslib-from-start/20260908T183629430908Z/foundation/Lean.vo'),
                          '--directory', str(stage / 'importer-regressions')]),
            ('runner', [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/tests']),
        ):
            print('Starting', name, flush=True)
            with (stage / (name + '.log')).open('x') as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            print('PASS', name, flush=True)
        if chunks.sha(chunks.WORKER) != worker_hash:
            raise RuntimeError('Worker changed during regressions')
        chunks.check_entries(source_hashes)
        stages = [r.stem for r in regressions] + ['full', 'reload']
        for name in stages:
            result = json.loads((stage / name / 'result.json').read_text())
            if result['worker_sha256'] != worker_hash or result['exit_code'] != 0:
                raise RuntimeError('Mismatched replay validation: ' + name)
        importer = json.loads((stage / 'importer-regressions/passed.json').read_text())
        if importer['worker_sha256'] != worker_hash or importer['tests'] != 44:
            raise RuntimeError('Mismatched importer validation')
        chunks.sha = lru_cache(maxsize=None)(chunks.sha)
        plan = json.loads((harness.CHECKPOINTS / 'plan.json').read_text())
        chunks.check_entries(chunks.generation_toolchain(plan)['inputs'])
        if chunks.sha(plan['export']) != plan['export_sha256']:
            raise RuntimeError('Export changed')
        verified = {}
        for chunk in plan['chunks']:
            if chunk['end'] <= harness.CHECKPOINT_END:
                migrations = chunks.verify_saved(harness.CHECKPOINTS, chunk)
                if migrations is None:
                    raise RuntimeError('Missing checkpoint: ' + chunk['module'])
                verified[chunk['module']] = migrations
        chunks.save_json(stage / 'verified-checkpoints.json', verified)
        chunks.save_json(stage / 'passed.json', {
            'worker_sha256': worker_hash, 'inputs': source_hashes,
            'stages': stages, 'full': str(stage / 'full'), 'reload': str(stage / 'reload'),
            'replay_start': 17000001, 'replay_end_exclusive': 17650001,
            'kernel_tests': 24, 'importer_tests': importer['tests'],
            'runner_log': str(stage / 'runner.log'),
        })
    print('VALIDATED', stage, worker_hash, flush=True)


if __name__ == '__main__':
    main()
