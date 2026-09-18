#!/usr/bin/env python3
"""Exercise strict checker CLI against actual serialized fixture flags."""
import json
from pathlib import Path
import re
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_cslib_ndjson as direct
import run_chunked_import as chunks


def main():
    name = sys.argv[1]
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        raise ValueError('Expected a fresh diagnostic directory name')
    directory = HERE / name
    directory.mkdir()
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    inputs = {str(checker): chunks.sha(checker), str(chunks.WORKER): chunks.sha(chunks.WORKER)}
    results = []
    for module, disabled in [('GuardDisabled', 'guard'), ('UniversesDisabled', 'universe'),
                             ('PositivityDisabled', 'positivity'), ('UIPEnabled', None)]:
        source = HERE / 'checker-profiles' / (module + '.v')
        inputs[str(source)] = chunks.sha(source)
        stage = directory / module
        subprocess.run([sys.executable, str(HERE / 'run.py'), str(source),
                        '--native', '--directory', str(stage)], check=True)
        artifact = stage / (module + '.vo')
        record = json.loads((stage / 'result.json').read_text())
        assert record['vo_sha256'] == chunks.sha(artifact)
        inputs[str(artifact)] = record['vo_sha256']
        base = [str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
                '-R', str(direct.checking.STDLIB), 'Stdlib', '-Q', str(stage), '', '-silent']
        cases = [('compatibility', [], None),
                 ('strict', ['-strict'],
                  'disabled ' + disabled + ' checking' if disabled else 'explicit -allow-uip')]
        if module == 'UIPEnabled':
            cases.extend([
                ('explicit-uip', ['-strict', '-allow-uip'], None),
                ('admit-rejected', ['-strict', '-allow-uip', '-admit', module],
                 'incompatible with -admit and -norec'),
                ('norec-rejected', ['-allow-uip', '-norec', module, '-strict'],
                 'incompatible with -admit and -norec')])
        for label, options, error in cases:
            command = ['bash', str(direct.checking.GUARD), 'timeout', '60s',
                       *base, *options, module]
            log = stage / (label + '.log')
            started = time.monotonic()
            with log.open('x') as output:
                result = subprocess.run(command, env=direct.environment(2048),
                                        stdout=output, stderr=subprocess.STDOUT)
            text = log.read_text()
            if error is None:
                assert result.returncode == 0, (module, label, text[-2000:])
            else:
                assert result.returncode != 0 and error in text, (module, label, text[-2000:])
            results.append({'module': module, 'case': label, 'command': command,
                            'exit_code': result.returncode,
                            'wall_seconds': time.monotonic() - started,
                            'expected_error': error})
            print('PASS', module, label, flush=True)
    chunks.check_entries(inputs)
    chunks.save_json(directory / 'passed.json', {'inputs': inputs, 'checks': results,
        'elimination_flag_note': 'Covered by direct CheckFlags policy unit test, not a vernacular flag fixture'})
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
