#!/usr/bin/env python3
"""Validate the eta-query quotation guard before allowing a full-run resume."""
import fcntl
from functools import lru_cache
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from run import replay as harness

HERE, ROOT, chunks = harness.HERE, harness.ROOT, harness.chunks
PREVIOUS = HERE.parent / 'mathlib-basic-open-repro'


def main():
    stage = Path(tempfile.mkdtemp(prefix='validation-', dir=HERE))
    print(stage, flush=True)
    worker_hash = chunks.sha(chunks.WORKER)
    regressions = [chunks.KERNEL / 'test-suite/success' / (name + '.v')
                   for name in ('unit_like_record', 'unit_like_aliases',
                                'projected_constant_congruence',
                                'congruence_probe_irrelevant',
                                'congruence_probe_irrelevant_prefix')]
    regressions += [PREVIOUS / name for name in
                    ('ClosureSyntax.v', 'HigherOrderClosure.v', 'StrategyBudget.v')]
    sources = [chunks.KERNEL / 'kernel/conversion.ml',
               chunks.KERNEL / 'kernel/cClosure.ml',
               chunks.KERNEL / 'kernel/cClosure.mli',
               chunks.KERNEL / 'test-suite/unit-tests/kernel/closure_inspection.ml',
               *regressions, HERE / 'full-source/MathlibTo20000000.v',
               HERE / 'Reload.v', HERE / 'run.py', HERE / 'validate.py',
               HERE / 'quotation_guard_test.ml', HERE / 'test-quotation-guard.sh',
               PREVIOUS / 'run.py', PREVIOUS / 'MathlibTo19000000.v',
               ROOT / 'work/int32-tdiv-repro/run-closure-inspection-test.sh',
               ROOT / 'work/structured-arrow-repro/validate.py',
               ROOT / 'work/blastadd-unary-repro/validate.py']
    source_hashes = {str(path): chunks.sha(path) for path in sources}
    stages = []

    def replay(name, source, *options):
        print('Starting', name, flush=True)
        with (stage / (name + '.log')).open('x') as log:
            subprocess.run([sys.executable, str(HERE / 'run.py'), str(source),
                            '--directory', str(stage / name), '--wait', *options],
                           cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        stages.append(name)
        print('PASS', name, flush=True)

    for source in regressions:
        options = ['--native']
        if source.name == 'HigherOrderClosure.v':
            options.append('--allow-rewrite-rules')
        replay(source.stem, source, *options)

    replay('full', HERE / 'full-source/MathlibTo20000000.v')
    replay('reload', HERE / 'Reload.v', '--prefix', str(stage / 'full'))
    replay('previous-full', PREVIOUS / 'MathlibTo19000000.v')

    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if chunks.sha(chunks.WORKER) != worker_hash:
            raise RuntimeError('Worker changed during replay')
        env = harness.direct.environment(4096)
        env['OCAMLPATH'] = str(chunks.KERNEL / '_build/install/default/lib') + ':' + env['OCAMLPATH']
        commands = (
            ('quotation', ['bash', str(HERE / 'test-quotation-guard.sh')]),
            ('closure-lifts', ['bash', str(ROOT / 'work/int32-tdiv-repro/run-closure-inspection-test.sh')]),
            ('kernel', [sys.executable, str(ROOT / 'work/structured-arrow-repro/validate.py')]),
            ('importer', [sys.executable, str(ROOT / 'work/blastadd-unary-repro/validate.py'),
                          '--foundation', str(ROOT / 'work/cslib-from-start/20260908T183629430908Z/foundation/Lean.vo'),
                          '--directory', str(stage / 'importer-regressions')]),
        )
        for name, command in commands:
            print('Starting', name, flush=True)
            with (stage / (name + '.log')).open('x') as log:
                subprocess.run(command, cwd=ROOT, env=env, stdout=log,
                               stderr=subprocess.STDOUT, check=True)
            print('PASS', name, flush=True)
        if chunks.sha(chunks.WORKER) != worker_hash:
            raise RuntimeError('Worker changed during regressions')
        chunks.check_entries(source_hashes)
        for name in stages:
            result = json.loads((stage / name / 'result.json').read_text())
            invocation = json.loads((stage / name / 'invocation.json').read_text())
            artifact = Path(invocation['command'][-1]).with_suffix('.vo')
            if (result['worker_sha256'] != worker_hash or result['exit_code'] != 0
                    or artifact.parent != (stage / name).resolve()
                    or chunks.sha(artifact) != result['vo_sha256']):
                raise RuntimeError('Mismatched replay: ' + name)
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
            'worker_sha256': worker_hash, 'inputs': source_hashes, 'stages': stages,
            'full': str(stage / 'full'), 'reload': str(stage / 'reload'),
            'previous_full': str(stage / 'previous-full'),
            'replay_start': 19000001, 'replay_end_exclusive': 20000001,
            'previous_start': 18000001, 'previous_end_exclusive': 19000001,
            'kernel_tests': 28, 'importer_tests': 44,
            'quotation_log': str(stage / 'quotation.log'),
            'closure_lifts_log': str(stage / 'closure-lifts.log'),
            'runner_results': 'Included in importer-regressions',
        })
    print('VALIDATED', stage, worker_hash, flush=True)


if __name__ == '__main__':
    main()
