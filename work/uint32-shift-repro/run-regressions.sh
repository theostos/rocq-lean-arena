#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
run_tag=${1:?Usage: run-regressions.sh UNIQUE_TAG}
[[ $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
for test in Target Fresh Widths Reload BoundedCongruence; do
  ROCQ_TEST_STACK_KIB=8192 bash "$repro_dir/run.sh" "$test" "$run_tag"
  printf 'PASS %s\n' "$test"
done
bash "$repo_dir/work/list-insert-erase-repro/run-regressions.sh" "$run_tag"
