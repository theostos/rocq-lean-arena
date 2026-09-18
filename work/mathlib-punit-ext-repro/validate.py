#!/usr/bin/env python3
"""Gate the wrapped-unit repair before resuming the canonical Mathlib chain."""
import fcntl
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from run import ROOT, HERE, CHECKPOINTS, chunks, direct


def main():
    stage = Path(tempfile.mkdtemp(prefix='validation-', dir=HERE))
    print('Validation:', stage, flush=True)
    worker_hash = chunks.sha(chunks.WORKER)
    conversion = chunks.KERNEL / 'kernel/conversion.ml'
    regression = chunks.KERNEL / 'test-suite/success/unit_like_record.v'
    source_hashes = {str(p): chunks.sha(p) for p in (conversion, regression)}

    def replay(name, source, *options):
        print('Starting', name, flush=True)
        with (stage / (name + '.log')).open('x') as log:
            subprocess.run([sys.executable, str(HERE / 'run.py'), str(source),
                            '--directory', str(stage / name), '--wait', *options],
                           cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
        print('PASS', name, flush=True)

    replay('wrapped-unit', regression, '--native')
    replay('full', HERE / 'MathlibTo14000000.v')
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
        ):
            print('Starting', name, flush=True)
            with (stage / (name + '.log')).open('x') as log:
                subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
            print('PASS', name, flush=True)
        if chunks.sha(chunks.WORKER) != worker_hash:
            raise RuntimeError('Worker changed during regressions')
        chunks.check_entries(source_hashes)
        for name in ('wrapped-unit', 'full', 'reload'):
            result = json.loads((stage / name / 'result.json').read_text())
            if result['worker_sha256'] != worker_hash or result['exit_code'] != 0:
                raise RuntimeError('Mismatched replay validation: ' + name)
        importer = json.loads((stage / 'importer-regressions/passed.json').read_text())
        if importer['worker_sha256'] != worker_hash:
            raise RuntimeError('Mismatched importer validation')
        chunks.save_json(stage / 'passed.json', {
            'worker_sha256': worker_hash, 'inputs': source_hashes,
            'full': str(stage / 'full'), 'reload': str(stage / 'reload'),
            'kernel_tests': 20, 'importer_tests': importer['tests'],
            'wrapped_unit_tests': str(stage / 'wrapped-unit/result.json'),
        })
    print('VALIDATED', stage, worker_hash, flush=True)


if __name__ == '__main__':
    main()
