#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
case ${1-} in
  ''|--check) ;;
  *) echo 'Usage: bash work/mathlib-proj-app-repro/resume.sh [--check]' >&2; exit 64 ;;
esac
export ROCQ_APPROVED_WORKER_SHA256=9645f46ccef126cb18fbba9f6cbf54356a98cce830e27d2e3190fcbccd6d701e
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

validation = Path('work/mathlib-proj-app-repro/validation-hsrd2ui6')
expected = os.environ['ROCQ_APPROVED_WORKER_SHA256']

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

try:
    passed = json.loads((validation / 'passed.json').read_text())
    worker = Path('_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe')
    if passed['worker_sha256'] != expected or sha(worker) != expected:
        raise ValueError('Worker does not match the validated repair')
    if (passed['replay_start'], passed['replay_end_exclusive']) != (13000001, 13650001):
        raise ValueError('Original-order replay range differs')
    for path, digest in passed['inputs'].items():
        if sha(path) != digest:
            raise ValueError('Repair source or regression changed: ' + path)
    required = ['unit_like_record', 'unit_like_aliases',
                'projected_constant_congruence', 'full', 'reload']
    if passed['kernel_tests'] != 23:
        raise ValueError('Kernel regression count differs')
    if passed['stages'] != required:
        raise ValueError('Required validation stages differ')
    for name in required:
        stage = validation / name
        result = json.loads((stage / 'result.json').read_text())
        invocation = json.loads((stage / 'invocation.json').read_text())
        artifact = Path(invocation['command'][-1]).with_suffix('.vo')
        if (result['exit_code'] != 0 or result['worker_sha256'] != expected
                or artifact.parent != stage.resolve()
                or sha(artifact) != result['vo_sha256']):
            raise ValueError('Replay or saved artifact differs: ' + name)
    importer = json.loads((validation / 'importer-regressions/passed.json').read_text())
    if importer['worker_sha256'] != expected or importer['tests'] != passed['importer_tests']:
        raise ValueError('Importer regression record differs')
except (OSError, ValueError, KeyError) as error:
    raise SystemExit('Repair validation incomplete or changed; refusing to resume: ' + str(error))
print('Validated projected-constant repair, 13M-to-13.65M replay and fresh reload match.', flush=True)
PY
if [[ ${1-} == --check ]]; then exit 0; fi
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800
