#!/usr/bin/env bash
# Sequential diagnostic validation only; never starts the production loop.
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
cd "$repo_dir"
while [[ ! -f $test_dir/riemannian-original-prefix/result.json ]]; do
  systemctl --user is-active --quiet rocq-riemann-prefix-validation.service || {
    printf 'Prefix service stopped without a result; refusing to build.\n' >&2
    exit 1
  }
  sleep 5
done
/usr/bin/python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["exit_code"])' \
  "$test_dir/riemannian-original-prefix/result.json"
bash work/mathlib-lift-to-discrete-repro/build.sh
sha256sum _worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe \
  _worktrees/rocq/compact-peano-view/_build/default/checker/rocqchk.exe
python3 work/kernel-alignment-pass/run.py \
  _worktrees/rocq/compact-peano-view/test-suite/success/typing_application_conversion_cache.v \
  --native --directory work/kernel-alignment-pass/typeops-cache-native
python3 "$test_dir/run-cache-traced.py" "$test_dir/RiemannianPreparedTargets.v" \
  "$test_dir/riemannian-typeops-cache-prepared" \
  --prefix "$test_dir/riemannian-original-prefix" --checkpoint-limit 25000000 --entries
