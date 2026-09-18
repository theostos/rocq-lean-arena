#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/lib
export COQBIN=$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/
export ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
exec bash "$repo_dir/work/run-memory-guarded.sh" \
  timeout --signal=TERM --kill-after=5s 300 \
  make -C "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current" \
    -f Makefile.rocq -j1 src/lean_import.cmxs
