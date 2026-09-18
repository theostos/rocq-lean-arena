#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
case ${1-} in
  ''|--check) ;;
  *) echo 'Usage: bash work/mathlib-basic-open-repro/resume.sh [--check]' >&2; exit 64 ;;
esac
export ROCQ_APPROVED_WORKER_SHA256=0343f4a860d43380cd111a3e700ed9bf5b464da10a1d08be353eb2b21e5a1db7
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

validation = Path('work/mathlib-basic-open-repro/validation-8gccux_c')
expected = os.environ['ROCQ_APPROVED_WORKER_SHA256']

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

try:
    passed = json.loads((validation / 'passed.json').read_text())
    worker = Path('_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe')
    if passed['worker_sha256'] != expected or sha(worker) != expected:
        raise ValueError('Worker does not match the validated repair')
    if (passed['replay_start'], passed['replay_end_exclusive']) != (18000001, 19000001):
        raise ValueError('Original-order replay range differs')
    for path, digest in passed['inputs'].items():
        if sha(path) != digest:
            raise ValueError('Repair source or regression changed: ' + path)
    required = ['unit_like_record', 'unit_like_aliases',
                'projected_constant_congruence', 'congruence_probe_irrelevant',
                'congruence_probe_irrelevant_prefix', 'ClosureSyntax',
                'HigherOrderClosure', 'StrategyBudget', 'full', 'reload']
    if passed['kernel_tests'] != 28 or passed['importer_tests'] != 44:
        raise ValueError('Regression counts differ')
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
    if importer['worker_sha256'] != expected or importer['tests'] != 44:
        raise ValueError('Importer regression record differs')
    kernel_directory = Path((validation / 'kernel.log').read_text().splitlines()[0])
    results = json.loads((kernel_directory / 'results.json').read_text())
    if len(results) != 20 or any(result['exit_code'] != 0 for result in results):
        raise ValueError('Broader kernel regression record differs')
    for result in results:
        original = Path(result['source'])
        staged = Path(result['log']).parent / original.name
        source = original.read_text()
        if original.name == 'compact_peano.v':
            source = source.replace('From Stdlib Require Import NArith.',
                                    'From Stdlib Require Import NArith.BinNat.')
        if staged.read_text() != source or not staged.with_suffix('.vo').is_file():
            raise ValueError('Broader kernel regression changed: ' + str(original))
    if 'closure substitution inspection: PASS' not in (validation / 'closure-lifts.log').read_text():
        raise ValueError('Closure-lifting unit test did not pass')
    verified = json.loads((validation / 'verified-checkpoints.json').read_text())
    if len(verified) != 18 or 'MathlibTo18000000' not in verified:
        raise ValueError('Original checkpoint chain verification differs')
except (OSError, ValueError, KeyError, IndexError) as error:
    raise SystemExit('Repair validation incomplete or changed; refusing to resume: ' + str(error))
print('Validated closure comparison repair, 18M-to-19M replay, fresh reload, '
      '28 kernel fixtures, closure-lifting unit test and 44 importer fixtures match.', flush=True)
PY
if [[ ${1-} == --check ]]; then exit 0; fi
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800
