"""Check that the runtime adapter changes only the four approved memory fields."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('memory_resume', HERE / 'resume-25gb.py')
resume = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resume)
chunks = resume.chunks
calls = []


def capture(*args, **kwargs):
    calls.append((args, kwargs))
    return subprocess.CompletedProcess(args, 0)


original = chunks.compile_module
with tempfile.TemporaryDirectory(prefix='rocq-memory-policy-test-') as scratch:
    attempt = Path(scratch)
    arguments = (resume.GENERATION / 'checkpoints', 'MemoryPolicyProbe',
                 attempt, False, attempt / 'unused-inputs')
    with patch.object(chunks, 'generation_toolchain', return_value={}):
        with patch.object(chunks.subprocess, 'run', side_effect=capture):
            original(*arguments)
        resume.memory_compiler(original, 2048 * 1024, capture)(*arguments)
        resume.memory_compiler(original, 3072 * 1024, capture)(*arguments)

assert len(calls) == 3
base_args, base_options = calls[0]
for index, reserve in [(1, 2048), (2, 3072)]:
    args, options = calls[index]
    assert args == base_args
    assert options['cwd'] == base_options['cwd']
    base, changed = base_options['env'], options['env']
    allowed = {'ROCQ_MAX_RSS_KIB', 'ROCQ_MEMORY_MAX_KIB',
               'ROCQ_MEMORY_HIGH_KIB', 'ROCQ_MIN_AVAILABLE_KIB'}
    assert set(changed) == set(base)
    assert all(changed[k] == base[k] for k in base if k not in allowed)
    assert changed['ROCQ_MEMORY_MAX_KIB'] == changed['ROCQ_MAX_RSS_KIB'] == str(resume.LIMIT_KIB)
    assert changed['ROCQ_MEMORY_HIGH_KIB'] == str(resume.LIMIT_KIB)
    assert changed['ROCQ_MIN_AVAILABLE_KIB'] == str(reserve * 1024)
    assert changed['ROCQ_MEMORY_SWAP_MAX_KIB'] == '0'
assert 25_000_000_000 - 1024 < resume.LIMIT_KIB * 1024 <= 25_000_000_000
try:
    resume.resource_environment(dict(base, ROCQ_MEMORY_SWAP_MAX_KIB='1'), 2048 * 1024)
except chunks.Refused:
    pass
else:
    raise AssertionError('Changed baseline policy was accepted')
assert chunks.compile_module is original
print('PASS: exact compiler command retained; only approved memory limits/reserve changed; no swap; fail closed.')
