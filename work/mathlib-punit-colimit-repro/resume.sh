#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
case ${1-} in
  ''|--check) ;;
  *) echo 'Usage: bash work/mathlib-punit-colimit-repro/resume.sh [--check]' >&2; exit 64 ;;
esac
export ROCQ_APPROVED_WORKER_SHA256=4c35ea0349dc0cb1c22d7d80acc6a456b9de9f31851af26be7868404f72415b3
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

validation = Path('work/mathlib-punit-colimit-repro/validation-qgnl0pow')
expected = os.environ['ROCQ_APPROVED_WORKER_SHA256']

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

try:
    passed = json.loads((validation / 'passed.json').read_text())
    worker = Path('_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe')
    if passed['worker_sha256'] != expected or sha(worker) != expected:
        raise ValueError('Worker does not match the validated repair')
    if (passed['replay_start'], passed['replay_end_exclusive']) != (13000001, 13100001):
        raise ValueError('Original-order replay range differs')
    for path, digest in passed['inputs'].items():
        if sha(path) != digest:
            raise ValueError('Repair source or regression changed: ' + path)
    required = ['unit_like_record', 'unit_like_aliases', 'full', 'reload']
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
print('Validated type-alias repair, 13M-to-13.1M replay and fresh reload match.', flush=True)
PY
if [[ ${1-} == --check ]]; then exit 0; fi
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800
