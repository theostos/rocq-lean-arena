#!/usr/bin/env python3
"""Independently recheck native fixture proofs and registrations (no admitted dependencies)."""
import json
import argparse
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
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('label', nargs='?', default='independent-check')
    parser.add_argument('--strict', action='store_true')
    parser.add_argument('--allow-uip', action='store_true',
                        help='Explicitly allow the definitional-UIP bridge in strict mode')
    args = parser.parse_args()
    if args.allow_uip and not args.strict:
        parser.error('--allow-uip requires --strict')
    directory = (HERE / args.directory).resolve(strict=True)
    if directory.parent != HERE:
        raise ValueError('Expected an alignment gate directory')
    label = args.label
    if not re.fullmatch(r'[A-Za-z0-9_-]+', label):
        raise ValueError('Expected a simple diagnostic label')
    checker = chunks.KERNEL / '_build/default/checker/rocqchk.exe'
    sources = sorted(directory.glob('*/result.json'))
    command = [str(checker), '-coqlib', str(chunks.KERNEL / '_build/install/default/lib/coq'),
               '-o', '-R', str(direct.checking.STDLIB), 'Stdlib']
    if args.strict:
        command.append('-strict')
        if args.allow_uip:
            command.append('-allow-uip')
    modules, artifacts = [], {}
    for result in sources:
        if not (result.parent / 'invocation.json').is_file():
            continue
        data = json.loads(result.read_text())
        if data['exit_code']:
            raise ValueError('Failed fixture: ' + str(result))
        artifact, = result.parent.glob('*.vo')
        if chunks.sha(artifact) != data['vo_sha256']:
            raise ValueError('Changed fixture: ' + str(artifact))
        artifacts[str(artifact)] = data['vo_sha256']
        command.extend(['-Q', str(result.parent), ''])
        modules.append(artifact.stem)
    gate_record = directory / 'passed.json'
    expected_count = json.loads(gate_record.read_text())['native_fixtures'] if gate_record.is_file() else 10
    if len(modules) != expected_count:
        raise ValueError(f'Expected all {expected_count} native fixtures')
    command.extend(modules)
    expected = {**artifacts, str(checker): chunks.sha(checker)}
    if gate_record.is_file():
        expected[str(gate_record)] = chunks.sha(gate_record)
    env = direct.environment(3072)
    started = time.monotonic()
    with (directory / (label + '.log')).open('x') as output:
        result = subprocess.run(['bash', str(direct.checking.GUARD), 'timeout', '180s', *command],
                                env=env, stdout=output, stderr=subprocess.STDOUT)
    chunks.check_entries(expected)
    chunks.save_json(directory / (label + '.json'), {
        'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
        'command': command, 'inputs': expected,
        'admitted_dependencies': False,
        'native_fixtures': len(modules),
        'strict_theory_profile': args.strict,
        'strict_profile': {
            'reject_disabled_checks': ['guard', 'positivity', 'universe', 'elimination'],
            'allow_definitional_uip': args.allow_uip,
            'allow_sprop': True,
            'allow_impredicative_set': False,
            'allow_vm': False,
            'allow_native_compiler': False,
        } if args.strict else None,
    })
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
