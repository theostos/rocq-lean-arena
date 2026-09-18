#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
case ${1-} in
  ''|--check) ;;
  *) echo 'Usage: bash work/mathlib-11m-investigation/resume.sh [--check]' >&2; exit 64 ;;
esac
export ROCQ_APPROVED_WORKER_SHA256=f8b61efc2d7c33f61f794be5f81d6a0d0f78c2f60ddcd64f43776f6f5212518a
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

root = Path('work/mathlib-11m-investigation')
try:
    validation = json.loads((root / 'validation-ok9bb35w/passed.json').read_text())
    reload = json.loads((root / 'full-vojwyug0/Reload.result.json').read_text())
except OSError:
    raise SystemExit('Repair validation is incomplete; do not resume yet.')
expected = os.environ['ROCQ_APPROVED_WORKER_SHA256']
worker = Path('_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe')
with worker.open('rb') as stream:
    actual = hashlib.file_digest(stream, 'sha256').hexdigest()
if (validation['worker_sha256'] != expected or reload['worker_sha256'] != expected
        or reload['exit_code'] != 0 or actual != expected):
    raise SystemExit('Worker or validation record differs from this repair.')
print('Validated worker and saved-proof reload match.', flush=True)
PY
if [[ ${1-} == --check ]]; then exit 0; fi
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800
