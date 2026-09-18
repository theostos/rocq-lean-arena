#!/usr/bin/env python3
"""Continue v7 qualification after repairing the checker deadline, reusing verified successes."""
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
CHAR = HERE.parent / 'mathlib-char-succ-repro'
OLDCHAR = HERE.parent / 'mathlib-char-ordinal-repro'
RIEM = HERE.parent / 'mathlib-riemann-sharing-repro'
LIE = HERE.parent / 'mathlib-lie-trace-repro'
GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
sys.path[:0] = [str(ROOT / 'scripts'), str(CHAR)]
import run_chunked_import as chunks
from resource_queue import archive_unstarted, wait_for_memory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tag', required=True)
    parser.add_argument('--consumer', required=True, type=Path)
    parser.add_argument('--worker-sha', required=True)
    parser.add_argument('--checker-sha', required=True)
    parser.add_argument('--slice', required=True, type=Path)
    args = parser.parse_args()
    assert re.fullmatch(r'etale-v[1-9][0-9]*', args.tag)
    consumer = args.consumer.resolve(strict=True)
    assert consumer.parent == ALIGN and consumer.name.startswith('importer.')
    slice_dir = args.slice.resolve(strict=True)
    assert slice_dir.parent == HERE
    record = json.loads((slice_dir / 'result.json').read_text())
    assert record['exit_code'] == 0 and record['worker_sha256'] == args.worker_sha
    assert record['module'] == 'EtaleWhole'
    assert chunks.sha(slice_dir / 'EtaleWhole.vo') == record['vo_sha256']
    chunks.check_entries(json.loads((slice_dir / 'invocation.json').read_text())['inputs'])
    tag = args.tag
    gate = ALIGN / ('final-gates-' + tag)
    assert tag == 'etale-v7'
    directory = HERE / 'validation-etale-v7-progress'
    previous = HERE / 'validation-etale-v7'
    old_progress = json.loads((previous / 'progress.json').read_text())
    old_inputs = json.loads((previous / 'inputs.json').read_text())
    chunks.check_entries(old_inputs)
    assert old_progress['phase'] == 'failed' and old_progress['step'] == 'original-independent'
    assert len(old_progress['results']) == 7
    assert [r['exit_code'] for r in old_progress['results']] == [0] * 6 + [124]
    original = HERE / ('original-' + tag)
    char_whole = CHAR / ('whole-' + tag)
    riemannian = RIEM / ('riemannian-' + tag)
    sset, lie, derivative = RIEM / ('sset-' + tag), LIE / ('proof-' + tag), RIEM / ('derivative-' + tag)
    commands = [
        ('gates', [ALIGN/'gates.py', gate.name]),
        ('native-independent', [ALIGN/'check-native.py', gate]),
        ('strict-native-independent', [ALIGN/'check-native.py', gate, 'strict-independent-check', '--strict', '--allow-uip']),
        ('strict-policy', [ALIGN/'test-strict-checker.py', 'strict-checker-' + tag]),
        ('etale-independent', [HERE/'check.py', slice_dir]),
        ('original-order', [HERE/'run.py', HERE/'MathlibTo35000000.v', original, '--checkpoint-limit', '30000000', '--entries']),
        ('original-independent', [HERE/'check-progress.py', original]),
        ('riemannian', [RIEM/'run-traced.py', RIEM/'RiemannianWholeFrom25M.v', riemannian, '--checkpoint-limit', '25000000']),
        ('riemannian-independent', [RIEM/'check-original-order.py', riemannian]),
        ('recursive-alias', [HERE/'run-small.py', CHAR/'FixPriority.v', HERE/('alias-' + tag)]),
        ('previous-char', [OLDCHAR/'run.py', OLDCHAR/'CharTarget.v', OLDCHAR/('target-' + tag), '--native', '--prefix', OLDCHAR/'prefix']),
        ('combined-char', [CHAR/'run.py', CHAR/'CharWhole.v', char_whole, '--native']),
        ('combined-independent', [CHAR/'check-slice.py', char_whole]),
        ('sset', [RIEM/'run-traced.py', RIEM/'SSetTarget.v', sset, '--native', '--prefix', RIEM/'sset-prefix']),
        ('sset-independent', [RIEM/'check-target.py', sset, RIEM/'sset-prefix', '--manifest', RIEM/'sset-slice.json']),
        ('lie', [LIE/'run.py', LIE/'ProofTarget.v', lie, '--native', '--prefix', LIE/'proof-prefix']),
        ('lie-independent', [RIEM/'check-target.py', lie, LIE/'proof-prefix']),
        ('derivative', [RIEM/'run-traced.py', RIEM/'DerivativeTarget.v', derivative, '--native', '--prefix', RIEM/'derivative-prefix']),
        ('derivative-independent', [RIEM/'check-target.py', derivative, RIEM/'derivative-prefix', '--manifest', RIEM/'derivative-slice.json']),
    ]
    inputs = {str(chunks.WORKER): args.worker_sha,
        str(chunks.KERNEL/'_build/default/checker/rocqchk.exe'): args.checker_sha}
    for folder in (chunks.KERNEL/'kernel', chunks.KERNEL/'checker',
                   chunks.KERNEL/'test-suite/success', chunks.KERNEL/'test-suite/unit-tests/kernel',
                   ALIGN, HERE):
        for path in folder.iterdir():
            if path.is_file() and path.suffix in {'.ml', '.mli', '.py', '.sh', '.v'}:
                inputs[str(path)] = chunks.sha(path)
    for _, command in commands:
        for arg in command:
            if isinstance(arg, Path) and arg.is_file():
                inputs[str(arg)] = chunks.sha(arg)
    for path in (slice_dir/'result.json', slice_dir/'invocation.json', slice_dir/'EtaleWhole.vo', CHAR/'resource_queue.py'):
        inputs[str(path)] = chunks.sha(path)
    for path, digest in old_inputs.items():
        assert path not in inputs or inputs[path] == digest, path
        inputs[path] = digest
    for path in (previous/'progress.json', previous/'inputs.json',
                 ROOT/'scripts/checker_progress.py', ROOT/'scripts/tests/test_checker_progress.py',
                 HERE/'deadline-tests.json', HERE/'deadline-tests.log'):
        inputs[str(path)] = chunks.sha(path)
    chunks.check_entries(inputs)
    directory.mkdir()
    chunks.save_json(directory/'inputs.json', inputs)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('LEAN_IMPORT_', 'ROCQ_', '_ROCQ_', 'ROCQLKA_'))}
    env.update(ROCQ_ALIGNMENT_IMPORTER=str(consumer), ROCQ_CHAR_SLICE_MEMORY_MIB='8192',
               ROCQ_LEGACY_MATHLIB_GENERATION=str(GENERATION))
    if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
        env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
    budgets = {'recursive-alias': 1024, 'previous-char': 8192, 'combined-char': 8192,
               'combined-independent': 4096, 'sset-independent': 3072,
               'lie-independent': 3072, 'derivative-independent': 3072,
               'native-independent': 3072, 'strict-native-independent': 3072}
    compile_dirs = {'original-order': original, 'riemannian': riemannian,
        'recursive-alias': HERE/('alias-' + tag), 'previous-char': OLDCHAR/('target-' + tag),
        'combined-char': char_whole, 'sset': sset, 'lie': lie, 'derivative': derivative}
    check_files = {'original-independent': (original, 'independent-progress'),
        'etale-independent': (slice_dir, 'independent'),
        'riemannian-independent': (riemannian, 'independent-original-order'),
        'combined-independent': (char_whole, 'independent'),
        'sset-independent': (sset, 'independent-target'),
        'lie-independent': (lie, 'independent-target'),
        'derivative-independent': (derivative, 'independent-target'),
        'native-independent': (gate, 'independent-check'),
        'strict-native-independent': (gate, 'strict-independent-check')}
    results, refusals = list(old_progress['results'][:6]), list(old_progress['refusals'])
    assert [r['label'] for r in results] == [label for label, _ in commands[:6]]
    for label, arguments in commands[6:]:
        command = [sys.executable, *map(str, arguments)]
        started, attempt = time.monotonic(), 0
        while True:
            def waiting(**memory):
                chunks.save_json(directory/'progress.json', {'phase': 'waiting_for_memory',
                    'step': label, 'results': results, 'refusals': refusals, **memory})
                print('WAIT', label, json.dumps(memory), flush=True)
            wait_for_memory(budgets.get(label, 16384), waiting)
            chunks.check_entries(inputs)
            print('START', label, 'attempt', attempt + 1, flush=True)
            chunks.save_json(directory/'progress.json', {'phase': 'running',
                'step': label, 'results': results, 'refusals': refusals})
            suffix = '' if attempt == 0 else f'-retry-{attempt}'
            with (directory/(label+suffix+'.log')).open('x') as output:
                result = subprocess.run(command, cwd=ROOT, env=env,
                                        stdout=output, stderr=subprocess.STDOUT)
            chunks.check_entries(inputs)
            archived = None
            if label in compile_dirs:
                stage = compile_dirs[label]
                archived = archive_unstarted(result.returncode, stage/'run.log',
                    stage/'result.json', fresh_directory=stage)
            elif label in check_files:
                stage, stem = check_files[label]
                archived = archive_unstarted(result.returncode, stage/(stem+'.log'), stage/(stem+'.json'))
            if archived is None:
                break
            refusals.append({'label': label, 'attempt': attempt + 1, 'archived': archived})
            attempt += 1
            time.sleep(15)
        results.append({'label': label, 'exit_code': result.returncode,
            'seconds': time.monotonic()-started, 'command': command,
            'memory_mib': budgets.get(label, 16384)})
        chunks.save_json(directory/'progress.json', {'results': results, 'refusals': refusals,
            'phase': 'failed' if result.returncode else 'stage_passed', 'step': label})
        print('END', label, result.returncode, results[-1]['seconds'], flush=True)
        if result.returncode:
            return result.returncode
    chunks.save_json(directory/'passed.json', {'exit_code': 0, 'inputs': inputs,
        'worker_sha256': args.worker_sha, 'checker_sha256': args.checker_sha,
        'consumer': str(consumer), 'tag': tag, 'slice': str(slice_dir),
        'results': results, 'refusals': refusals, 'max_memory_mib': 16384, 'reserve_mib': 3072,
        'reused_validation': str(previous), 'reused_stages': 6,
        'deadline_policy': 'original-independent now uses 1800s per declaration progress; binary unchanged',
        'scope': 'Proof-preserving slices and original-order segments; not full Mathlib acceptance'})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
