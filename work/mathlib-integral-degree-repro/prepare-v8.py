#!/usr/bin/env python3
"""Build the cache candidate, check the exact Etale proof, then qualify/resume.

Never resume on a diagnostic result alone. The existing full qualification and
promotion checks must pass with the new worker/checker before the 30M resume.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ALIGN = HERE.parent / 'kernel-alignment-pass'
ETALE = HERE.parent / 'mathlib-etale-repro'
KERNEL = ROOT / '_worktrees/rocq/compact-peano-view'
IMPORTER_SOURCE = ALIGN / 'importer.eZWQ15ef'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--attempt', type=int, default=1)
args = parser.parse_args()
if args.attempt < 1:
    parser.error('attempt must be positive')
OUT = HERE / ('prepare-v8' if args.attempt == 1 else f'prepare-v8-attempt-{args.attempt}')
sys.path[:0] = [str(ROOT / 'scripts'), str(HERE.parent / 'mathlib-char-succ-repro')]
import run_chunked_import as chunks
from resource_queue import archive_unstarted, wait_for_memory


def status(phase, **details):
    chunks.save_json(OUT / 'status.json', {
        'phase': phase, 'updated_unix': time.time(),
        'qualification_status': str(ETALE / 'finish-status-etale-v8.json'),
        'production_monitoring': False, **details})
    print(phase, json.dumps(details), flush=True)


def main():
    OUT.mkdir()
    paths = [Path(__file__), HERE / 'build-integrated.sh']
    for folder in (KERNEL / 'kernel', KERNEL / 'checker',
                   KERNEL / 'test-suite/unit-tests/kernel', KERNEL / 'test-suite/success',
                   ALIGN, ETALE, IMPORTER_SOURCE / 'src'):
        paths.extend(p for p in folder.iterdir()
                     if p.is_file() and p.suffix in {'.ml', '.mli', '.mlg', '.py', '.sh', '.v'})
    inputs = {str(p): chunks.sha(p) for p in paths}
    chunks.save_json(OUT / 'inputs.json', inputs)
    proof = HERE / 'suspended-v4-full/result.json'
    status('waiting_for_complete_diagnostic', proof=str(proof))
    while not proof.exists():
        chunks.check_entries(inputs)
        time.sleep(15)
    result = json.loads(proof.read_text())
    if result['exit_code'] != 0 or not result['checked_target']:
        raise RuntimeError('The complete diagnostic proof did not pass')
    inputs[str(proof)] = chunks.sha(proof)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
        env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']

    def run(label, command, memory_mib, *, directory=None, independent=False):
        attempt = 0
        while True:
            wait_for_memory(memory_mib, lambda **memory:
                status('waiting_for_memory', step=label, **memory))
            chunks.check_entries(inputs)
            status('running', step=label, memory_mib=memory_mib)
            log = OUT / (label + (f'-retry-{attempt}' if attempt else '') + '.log')
            with log.open('x') as stream:
                process = subprocess.run(list(map(str, command)), cwd=ROOT, env=env,
                                         stdout=stream, stderr=subprocess.STDOUT)
            chunks.check_entries(inputs)
            archived = None
            if directory is not None:
                archived = archive_unstarted(process.returncode,
                    directory / ('independent.log' if independent else 'run.log'),
                    directory / ('independent.json' if independent else 'result.json'),
                    fresh_directory=None if independent else directory)
            if archived is None:
                break
            attempt += 1
            status('admission_refused', step=label, archived=archived)
        if process.returncode:
            raise RuntimeError(f'{label} failed with exit {process.returncode}; see {log}')
        return log

    run('build-core', ['bash', HERE / 'build-integrated.sh'], 3072)
    run('build-plugins', ['bash', ALIGN / 'build-plugins.sh'], 3072)
    # Only recompile the previously validated importer against the new kernel.
    # Do not incorporate any unrelated development from its source worktree.
    env['ROCQ_ALIGNMENT_IMPORTER_SOURCE'] = str(IMPORTER_SOURCE)
    log = run('build-importer', ['bash', ALIGN / 'build-importer.sh'], 3072)
    matches = re.findall(r'^Staged importer: (.+)$', log.read_text(), re.MULTILINE)
    if len(matches) != 1:
        raise RuntimeError('Could not identify the fresh importer')
    consumer = Path(matches[0]).resolve(strict=True)
    if consumer.parent != ALIGN or not consumer.name.startswith('importer.'):
        raise RuntimeError('Unexpected importer path')
    env['ROCQ_ALIGNMENT_IMPORTER'] = str(consumer)
    worker = KERNEL / '_build/default/topbin/rocqworker.exe'
    checker = KERNEL / '_build/default/checker/rocqchk.exe'
    worker_sha, checker_sha = chunks.sha(worker), chunks.sha(checker)
    inputs.update({str(worker): worker_sha, str(checker): checker_sha})
    chunks.save_json(OUT / 'candidate.json', {'worker_sha256': worker_sha,
        'checker_sha256': checker_sha, 'consumer': str(consumer), 'inputs': inputs})
    target = ETALE / 'candidate-target-v8-production-budget'
    run('exact-target', [sys.executable, ETALE / 'run.py',
        ETALE / 'EtaleTargetProductionBudget.v', target,
        '--native', '--prefix', ETALE / 'proof-prefix'], 16384, directory=target)
    run('exact-independent', [sys.executable, ETALE / 'check.py', target], 16384,
        directory=target, independent=True)
    run('qualification-and-resume', [sys.executable, ETALE / 'finish-v8.py',
        '--consumer', consumer, '--worker-sha', worker_sha, '--checker-sha', checker_sha], 3072)
    status('production_launched', service='rocq-mathlib-alignment-5m-etale-v8.service',
           monitoring=False)


if __name__ == '__main__':
    if OUT.exists():
        raise FileExistsError(f'Attempt already exists: {OUT}')
    try:
        main()
    except Exception as error:
        if OUT.exists():
            status('failed', reason=str(error), automatic_resume=False)
        raise
