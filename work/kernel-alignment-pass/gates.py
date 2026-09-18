#!/usr/bin/env python3
"""Sequential candidate gates, including a fresh foundation and importer fixtures."""
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import mathlib_ndjson_loop as loop


def importer_gates(importer, foundation, directory):
    candidate = runpy.run_path(str(ROOT / 'work/blastadd-unary-repro/validate.py'))
    gate = candidate['gate']
    # The regression corpus lives in the earlier fixture worktree. Keep that
    # source/dump location distinct from the runtime plugin being validated.
    gate.PLUGIN = importer / 'src/lean_import.cmxs'
    compile_test = gate.compile_test

    def compile_candidate(*args):
        fixtures = gate.IMPORTER
        findlib = os.environ.get('OCAMLPATH')
        gate.IMPORTER = importer
        os.environ['OCAMLPATH'] = ':'.join((
            str(loop.chunks.KERNEL / '_build/install/default/lib'),
            str(importer / '_build/findlib')))
        try:
            return compile_test(*args)
        finally:
            gate.IMPORTER = fixtures
            if findlib is None:
                os.environ.pop('OCAMLPATH', None)
            else:
                os.environ['OCAMLPATH'] = findlib

    gate.compile_test = compile_candidate
    gate.validate(None, directory, foundation)


def main():
    importer = Path(os.environ['ROCQ_ALIGNMENT_IMPORTER']).resolve(strict=True)
    if importer.parent != HERE or not importer.name.startswith('importer.'):
        raise ValueError('Expected isolated candidate importer')
    directory = HERE / sys.argv[1]
    if directory.parent != HERE or directory.exists():
        raise ValueError('Expected a new alignment gate directory name')
    directory.mkdir()
    loop.direct.checking.IMPORTER = importer
    worker_hash = loop.chunks.sha(loop.chunks.WORKER)
    sources = {
        str(path): loop.chunks.sha(path)
        for path in (importer / 'src').iterdir()
        if path.suffix in ('.ml', '.mli', '.mlg', '.cmxs')
    }
    # Pin source-level private tests as well as the executing artifacts.
    # Later source-only work must not retroactively change what a gate certifies.
    source_inputs = {}
    for folder in ('kernel', 'checker', 'test-suite/unit-tests/kernel', 'test-suite/success'):
        for path in (loop.chunks.KERNEL / folder).iterdir():
            if path.is_file() and path.suffix in ('.ml', '.mli', '.v'):
                source_inputs[str(path)] = loop.chunks.sha(path)
    for path in HERE.iterdir():
        if path.is_file() and path.suffix in ('.ml', '.py', '.sh'):
            source_inputs[str(path)] = loop.chunks.sha(path)
    for path in (ROOT / 'scripts/tests').glob('test_*.py'):
        source_inputs[str(path)] = loop.chunks.sha(path)
    runner_gate = ROOT / 'scripts/checkpoint_generation.py'
    source_inputs[str(runner_gate)] = loop.chunks.sha(runner_gate)
    legacy_validator = ROOT / 'work/structured-arrow-repro/validate.py'
    source_inputs[str(legacy_validator)] = loop.chunks.sha(legacy_validator)
    loop.chunks.save_json(directory / 'source-inputs.json', source_inputs)

    # Runner/resource/checkpoint tests exercise restart safety without changing
    # the real generation. Preserve the complete report and explicit skips.
    runner_command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/tests']
    with (directory / 'runner-tests.log').open('x') as log:
        runner = subprocess.run(runner_command, cwd=ROOT,
                                stdout=log, stderr=subprocess.STDOUT)
    report = (directory / 'runner-tests.log').read_text()
    match = re.search(r'Ran (\d+) tests? in ', report)
    if runner.returncode or match is None:
        raise RuntimeError('Runner regression suite failed: ' + str(directory / 'runner-tests.log'))
    skipped = re.search(r'^OK \(skipped=(\d+)\)', report, re.MULTILINE)
    loop.chunks.save_json(directory / 'runner-tests.json', {
        'exit_code': runner.returncode, 'command': runner_command,
        'tests': int(match[1]), 'skipped': int(skipped[1]) if skipped else 0,
        'inputs': source_inputs,
        'outputs': {str(directory / 'runner-tests.log'): loop.chunks.sha(directory / 'runner-tests.log')}})
    subprocess.run([sys.executable, str(HERE / 'test-consumer-toolchain.py')], check=True)
    subprocess.run(['bash', str(HERE / 'test-quotation.sh')], check=True)
    subprocess.run(['bash', str(HERE / 'test-witness-candidate.sh')], check=True)
    subprocess.run(['bash', str(HERE / 'test-typeops-cache.sh')], check=True)
    subprocess.run(['bash', str(HERE / 'test-checker-typing.sh')], check=True)
    subprocess.run(['bash', str(HERE / 'test-closure-candidate.sh')], check=True)
    subprocess.run([sys.executable, str(HERE / 'test-digests.py')], check=True)
    native = '''projected_discarded_parameters typing_application_conversion_cache abbrev_congruence_order unit_like_registration_quality compact_peano_sharing
        compact_peano_registration_order compact_peano_registration_universes
        unit_like_record unit_like_aliases projected_constant_congruence projected_argument_order
        congruence_probe_irrelevant congruence_probe_irrelevant_prefix
        opaque_unit_alias dependent_unit_projection unit_like_cases unit_like_type_families
        unit_like_function_transport unit_like_recursive_families'''.split()
    for name in native:
        source = loop.chunks.KERNEL / 'test-suite/success' / (name + '.v')
        subprocess.run([sys.executable, str(HERE / 'run.py'), str(source),
                        '--native', '--directory', str(directory / name)], check=True)

    legacy = runpy.run_path(str(legacy_validator))
    legacy['direct'].checking.IMPORTER = importer
    if legacy['main'](generation=os.environ.get('ROCQ_LEGACY_MATHLIB_GENERATION'),
                      directory=directory / 'legacy-regressions'):
        return 1

    # Build the foundation and execute a small sealed, original-order NDJSON
    # generation from line 1. Historical proof artifacts are not inputs here.
    fresh = directory / 'fresh-smoke'
    if loop.run(fresh, smoke=True, memory_mib=2048):
        return 1
    importer_gates(importer, fresh / 'foundation/Lean.vo', directory / 'importer-regressions')
    loop.chunks.check_entries(sources)
    loop.chunks.check_entries(source_inputs)
    assert worker_hash == loop.chunks.sha(loop.chunks.WORKER)
    loop.chunks.save_json(directory / 'passed.json', {
        'worker_sha256': worker_hash, 'native_fixtures': len(native),
        'runtime_unit_families': [
            'closure_quotation', 'closure_snapshot', 'closure_inspection',
            'closure_lifting', 'private_demand_sharing', 'private_type_query', 'unit_type_witness', 'constant_deps',
            'syntax_lifting', 'syntax_substitution', 'syntax_module_substitution',
            'typeops_application_conversions', 'checker_typed_conversion',
            'projection_congruence_segments', 'projection_argument_order',
            'projection_mismatched_fields', 'lazy_projection_sources',
            'suspended_conversion_cache', 'original_expression_lookup',
            'exposed_lambda_cache', 'sharing_aware_syntax_probe',
            'sharing_aware_alpha_probe'],
        'legacy_fixtures': 20, 'fresh_smoke': str(fresh / 'result.json'),
        'legacy_regressions': str(directory / 'legacy-regressions/passed.json'),
        'runner_tests': str(directory / 'runner-tests.json'),
        'importer_regressions': str(directory / 'importer-regressions/passed.json'),
        'consumer_importer_inputs': sources,
        'source_inputs': source_inputs,
    })
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
