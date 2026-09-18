#!/usr/bin/env python3
"""Small kernel regression fixtures, not the full importer/Mathlib suite."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('directory', type=Path)
args = parser.parse_args()
directory = args.directory.resolve()
assert directory.parent == HERE and not directory.exists()
tests = chunks.KERNEL / 'test-suite/success'
fixtures = [tests / (name + '.v') for name in (
    'case_inversion_conversion', 'unit_like_function_transport',
    'unit_like_computed_discriminants', 'projected_discarded_parameters',
    'projected_argument_order', 'projected_constant_congruence',
    'direct_unfolding_dependency', 'abbrev_congruence_order',
    'eta_before_computation', 'projection_before_eta', 'record_postponed_eta',
    'congruence_probe_scope', 'congruence_probe_irrelevant',
    'congruence_probe_irrelevant_prefix', 'bounded_congruence',
    'typing_application_conversion_cache', 'apply_template')]
fixtures.append(HERE.parent / 'mathlib-cotangent-repro/AppliedProjectionAliases.v')
inputs = {str(p): chunks.sha(p) for p in (
    Path(__file__), chunks.WORKER, chunks.KERNEL / 'kernel/conversion.ml',
    direct.checking.GUARD, *fixtures, *direct.checking.STDLIB.rglob('*.vo'))}
chunks.check_entries(inputs)
directory.mkdir()
env = direct.environment(2048)
results = []
started = time.monotonic()
for fixture in fixtures:
    target = directory / fixture.name
    target.write_bytes(fixture.read_bytes())
    command = ['bash', str(direct.checking.GUARD), 'timeout', '--kill-after=5s', '60s',
        str(chunks.WORKER), '--kind=compile', '-coqlib', env['COQLIB'],
        '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
        '-Q', str(directory), '', str(target)]
    start = time.monotonic()
    with target.with_suffix('.log').open('x') as log:
        result = subprocess.run(command, env=env, cwd=directory,
                                stdout=log, stderr=subprocess.STDOUT)
    entry = dict(module=target.stem, exit_code=result.returncode,
                 wall_seconds=time.monotonic()-start, command=command)
    if result.returncode == 0:
        entry['vo_sha256'] = chunks.sha(target.with_suffix('.vo'))
    results.append(entry)
    print(json.dumps(entry), flush=True)
    if result.returncode:
        break
chunks.check_entries(inputs)
exit_code = results[-1]['exit_code']
chunks.save_json(directory / 'result.json', dict(
    exit_code=exit_code, wall_seconds=time.monotonic()-started, inputs=inputs,
    worker_sha256=inputs[str(chunks.WORKER)], fixtures=results,
    outputs={str(directory / (r['module'] + '.vo')): r['vo_sha256']
             for r in results if r['exit_code'] == 0}))
raise SystemExit(exit_code)
