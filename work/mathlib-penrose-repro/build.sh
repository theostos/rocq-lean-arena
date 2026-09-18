#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export ROCQ_MAX_RSS_KIB=2621440 ROCQ_MEMORY_MAX_KIB=3145728
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
exec bash "$repo_dir/work/run-memory-guarded.sh" \
  timeout --kill-after=5s 300s dune build --root "$repo_dir/_worktrees/rocq/compact-peano-view" \
  -j1 topbin/rocqworker.exe checker/rocqchk.exe
