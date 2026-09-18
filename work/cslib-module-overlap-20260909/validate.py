#!/usr/bin/env python3
"""Compare two predicted groups with actual standalone lean4export output."""
from collections import Counter
import json
import pickle
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SOURCE = ROOT / '_deps/lean-kernel-arena/_build/tests/work/cslib/src'
EXPORTER = ROOT / '_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export'
CASES = ['Cslib.Computability.Automata.DA.Buchi',
         'Cslib.Foundations.Control.Monad.Free.Fold',
         'Cslib-selected-union']


def main():
    if not Path('/proc/self/cgroup').read_text().strip().endswith('/rocq-lean-import-heavy.scope'):
        raise RuntimeError('run the validation exports inside the shared memory guard')
    seeds = {name: [] for name in CASES}
    selected_keys = []
    predictions = {g['module']: g for g in json.loads((HERE / 'groups.json').read_text())
                   if g['scenario'] == 'owned_declarations'}
    with (HERE / 'parsed.pickle').open('rb') as f:
        parsed = pickle.load(f)
    exported = set(parsed[1][1])
    del parsed
    with (HERE / 'metadata.jsonl').open() as f:
        header = json.loads(next(f))
        for idx, line in enumerate(f):
            r = json.loads(line)
            module = header['modules'][r[1]] if r[1] is not None else ''
            if idx in exported and not r[3]:
                if module in seeds:
                    seeds[module].append(r[6])
                if module in predictions:
                    seeds['Cslib-selected-union'].append(r[6])
                    selected_keys.append(r[0])
    summary = json.loads((HERE / 'summary.json').read_text())['scenarios']['owned_declarations']
    predictions['Cslib-selected-union'] = {'entries': summary['entries']['unique'],
        'expression_nodes': summary['expression_nodes']['unique']}
    requested = sys.argv[1:] or CASES
    assert set(requested) <= set(CASES)
    output_record = HERE / 'validation.json'
    validations = [r for r in json.loads(output_record.read_text()) if r['module'] not in requested] \
        if output_record.exists() else []
    for module in requested:
        path = HERE / (module + '.ndjson')
        command = ['lake', 'env', str(EXPORTER), 'Cslib', '--', *sorted(seeds[module])]
        if module == 'Cslib-selected-union':
            selected_file = HERE / 'selected-name-keys.json'
            selected_file.write_text(json.dumps(selected_keys) + '\n')
            lean_path = subprocess.check_output(['lake', 'env', 'printenv', 'LEAN_PATH'],
                                               cwd=SOURCE, text=True).strip()
            exporter_lib = EXPORTER.parents[1] / 'lib/lean'
            command = ['lake', 'env', 'env', f'LEAN_PATH={exporter_lib}:{lean_path}',
                       'lean', '--run', str(HERE / 'ExportSelected.lean'), str(selected_file)]
        print('exporting', module, flush=True)
        started = time.monotonic()
        with path.open('wb') as out:
            subprocess.run(command, cwd=SOURCE, stdout=out, check=True)
        counts = Counter()
        with path.open('rb') as f:
            for raw in f:
                row = json.loads(raw)
                if 'ie' in row:
                    counts['expression_nodes'] += 1
                elif 'inductive' in row:
                    counts['entries'] += len(row['inductive']['types'])
                    counts['named_constants'] += sum(len(row['inductive'][k]) for k in ('types','ctors','recs'))
                elif 'quot' in row:
                    counts['entries'] += int(row['quot']['kind'] == 'type')
                    counts['named_constants'] += 1
                elif any(k in row for k in ('def','thm','opaque','axiom')):
                    counts['entries'] += 1
                    counts['named_constants'] += 1
        expected = predictions[module]
        assert counts['entries'] == expected['entries'], (module, counts, expected)
        assert counts['expression_nodes'] == expected['expression_nodes'], (module, counts, expected)
        if 'reachable_constants' in expected:
            assert counts['named_constants'] == expected['reachable_constants'], (module, counts, expected)
        record = {'module': module, 'counts': dict(counts), 'matches_prediction': True,
                  'elapsed_seconds': time.monotonic() - started, 'command': command}
        validations.append(record)
        print(json.dumps({k: v for k, v in record.items() if k != 'command'}), flush=True)
    (HERE / 'validation.json').write_text(json.dumps(validations, indent=2) + '\n')


if __name__ == '__main__':
    main()
