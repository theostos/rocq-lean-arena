#!/usr/bin/env python3
"""Validate the final worker after the isolated replay releases its lock."""
import fcntl
import json
from pathlib import Path
import subprocess
import sys
import tempfile

from reproduce import ROOT, HERE, chunks, direct


def main():
    replay = Path(sys.argv[1]).resolve(strict=True)
    stage = Path(tempfile.mkdtemp(prefix='validation-', dir=HERE))
    print('Validation logs:', stage, flush=True)
    print('Waiting for the isolated replay; no concurrent heavy worker.', flush=True)
    with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        result = json.loads((replay / 'result.json').read_text())
        if result['exit_code'] != 0:
            raise RuntimeError('Replay failed; repair it before final validation')
        worker_hash = chunks.sha(chunks.WORKER)
        env = direct.environment(4096)

        def run(name, command, guarded=True):
            if guarded:
                command = ['bash', str(direct.checking.GUARD), 'timeout', '180s', *command]
            with (stage / (name + '.log')).open('x') as output:
                subprocess.run(command, cwd=stage, env=env, stdout=output,
                               stderr=subprocess.STDOUT, check=True)
            print('PASS', name, flush=True)

        compiler = ['ocamlfind', 'ocamlopt', '-rectypes', '-thread',
                    '-package', 'rocq-runtime.kernel']
        source = chunks.KERNEL / 'test-suite/unit-tests/kernel/constant_deps.ml'
        run('dependencies-build', [*compiler, '-c', str(source), '-o', str(stage / 'constant_deps.cmx')])
        run('dependencies-link', [*compiler, '-linkpkg', str(stage / 'constant_deps.cmx'),
                                  '-o', str(stage / 'constant_deps.exe')])
        run('dependencies', [str(stage / 'constant_deps.exe')])
        run('kernel-regressions', [sys.executable, str(ROOT / 'work/structured-arrow-repro/validate.py')], False)
        run('importer-regressions', [sys.executable, str(ROOT / 'work/blastadd-unary-repro/validate.py'),
            '--foundation', str(ROOT / 'work/cslib-from-start/20260908T183629430908Z/foundation/Lean.vo'),
            '--directory', str(stage / 'importer-regressions')], False)
        if chunks.sha(chunks.WORKER) != worker_hash:
            raise RuntimeError('Worker changed during validation')
        chunks.save_json(stage / 'passed.json', {
            'worker_sha256': worker_hash, 'replay': str(replay),
            'kernel_tests': 20,
            'dependency_tests_sha256': chunks.sha(source),
            'environ_sha256': chunks.sha(chunks.KERNEL / 'kernel/environ.ml'),
            'importer_results': str(stage / 'importer-regressions/passed.json')})
        print('Final worker validation passed:', worker_hash, flush=True)


if __name__ == '__main__':
    main()
