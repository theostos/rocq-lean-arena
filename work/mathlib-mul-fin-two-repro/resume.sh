#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
case ${1-} in
  ''|--check) ;;
  *) echo 'Usage: bash work/mathlib-mul-fin-two-repro/resume.sh [--check]' >&2; exit 64 ;;
esac
export ROCQ_APPROVED_WORKER_SHA256=fdb0d78a70bedd2215f0216bad820f5d745c78129622f8be8c4fabe7e6bc4ad5
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

validation = Path('work/mathlib-mul-fin-two-repro/validation-3yinq_w6')
expected = os.environ['ROCQ_APPROVED_WORKER_SHA256']

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

try:
    passed = json.loads((validation / 'passed.json').read_text())
    worker = Path('_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe')
    if passed['worker_sha256'] != expected or sha(worker) != expected:
        raise ValueError('Worker does not match the validated repair')
    if (passed['replay_start'], passed['replay_end_exclusive']) != (17000001, 17650001):
        raise ValueError('Original-order replay range differs')
    for path, digest in passed['inputs'].items():
        if sha(path) != digest:
            raise ValueError('Repair source or regression changed: ' + path)
    required = ['unit_like_record', 'unit_like_aliases',
                'projected_constant_congruence', 'congruence_probe_irrelevant',
                'full', 'reload']
    if passed['kernel_tests'] != 24 or passed['importer_tests'] != 44:
        raise ValueError('Regression counts differ')
    if passed['stages'] != required:
        raise ValueError('Required validation stages differ')
    # The prefix compatibility control was added while the main validation
    # was running. Require its independent result from the same frozen worker.
    extra = 'congruence_probe_irrelevant_prefix'
    for name in required + [extra]:
        stage = validation / ('prefix-control-final' if name == extra else name)
        result = json.loads((stage / 'result.json').read_text())
        invocation = json.loads((stage / 'invocation.json').read_text())
        artifact = Path(invocation['command'][-1]).with_suffix('.vo')
        if (result['exit_code'] != 0 or result['worker_sha256'] != expected
                or artifact.parent != stage.resolve()
                or sha(artifact) != result['vo_sha256']):
            raise ValueError('Replay or saved artifact differs: ' + name)
        if name == extra:
            source = Path('_worktrees/rocq/compact-peano-view/test-suite/success') / (extra + '.v')
            if source.read_text() != invocation['source']:
                raise ValueError('Prefix control source changed')
    importer = json.loads((validation / 'importer-regressions/passed.json').read_text())
    if importer['worker_sha256'] != expected or importer['tests'] != passed['importer_tests']:
        raise ValueError('Importer regression record differs')
    verified = json.loads((validation / 'verified-checkpoints.json').read_text())
    if len(verified) != 17 or 'MathlibTo17000000' not in verified:
        raise ValueError('Original checkpoint chain verification differs')
except (OSError, ValueError, KeyError) as error:
    raise SystemExit('Repair validation incomplete or changed; refusing to resume: ' + str(error))
print('Validated erased-proof fallback, 17M-to-17.65M replay, fresh reload and 25 kernel fixtures match.', flush=True)
PY
if [[ ${1-} == --check ]]; then exit 0; fi
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800
