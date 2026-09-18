#!/usr/bin/env python3
"""Read-only consistency checks for the serial qualification and resume guard."""
import ast
from pathlib import Path

HERE = Path(__file__).resolve().parent


def assigned(module, name):
    matches = [node.value for node in ast.walk(module) if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == name for target in node.targets)]
    assert len(matches) == 1, (name, len(matches))
    return matches[0]


validation = ast.parse((HERE / 'validate.py').read_text())
resume = ast.parse((HERE / 'resume.py').read_text())
commands = assigned(validation, 'commands')
labels = [ast.literal_eval(command.elts[0]) for command in commands.elts]
expected = ast.literal_eval(assigned(resume, 'expected'))
assert labels == expected and len(labels) == len(set(labels)) == 19
gates = ast.parse((HERE.parent / 'kernel-alignment-pass/gates.py').read_text())
native = assigned(gates, 'native')
assert isinstance(native, ast.Call) and native.func.attr == 'split'
native_names = ast.literal_eval(native.func.value).split()
assert len(native_names) == len(set(native_names)) == 19
assert {'projected_argument_order', 'projected_discarded_parameters'} <= set(native_names)
assert {'etale-independent', 'original-order', 'original-independent',
        'gates', 'strict-native-independent', 'strict-policy',
        'riemannian', 'sset', 'lie', 'derivative', 'combined-char'} <= set(labels)

finish = ast.parse((HERE / 'finish.py').read_text())
steps = assigned(finish, 'steps')
assert [ast.literal_eval(step.elts[0]) for step in steps.elts] == [
    'full_slice', 'validation', 'promotion_check', 'resume']
for name in ('finish.py', 'resume.py'):
    source = (HERE / name).read_text()
    assert 'etale-v1' not in source and 'importer.WgVIbhEO' not in source
    assert 'etale-v7' in source and 'importer.eZWQ15ef' in source
for name in ('EtaleWhole.v', 'MathlibTo35000000.v'):
    source = (HERE / name).read_text()
    assert 'Set Lean Line Timeout 1800.' in source
    assert 'Unset Lean Just Parsing.' in source
    assert 'Unset Lean Lazy Instantiation.' in source
assert "'projection_mismatched_fields', 'lazy_projection_sources'" in (
    HERE / 'resume.py').read_text()

# Verify that each known regression source/prefix is still present. Do not
# rehash large proof artifacts or launch compilers in this lightweight test.
base = HERE.parent
for relative in (
    'mathlib-char-succ-repro/FixPriority.v',
    'mathlib-char-succ-repro/CharWhole.v',
    'mathlib-char-ordinal-repro/CharTarget.v',
    'mathlib-char-ordinal-repro/prefix/result.json',
    'mathlib-riemann-sharing-repro/RiemannianWholeFrom25M.v',
    'mathlib-riemann-sharing-repro/SSetTarget.v',
    'mathlib-riemann-sharing-repro/sset-prefix/result.json',
    'mathlib-riemann-sharing-repro/DerivativeTarget.v',
    'mathlib-riemann-sharing-repro/derivative-prefix/result.json',
    'mathlib-lie-trace-repro/ProofTarget.v',
    'mathlib-lie-trace-repro/proof-prefix/result.json',
):
    assert (base / relative).is_file(), relative
print('Qualification plan:19 distinct stages agree with the resume guard; regression inputs exist.')
