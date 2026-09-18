#!/usr/bin/env bash
set -Eeuo pipefail
task_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=/home/theo/Documents/github/rocq-lean-typechecker
stock=$repo_root/_worktrees/review/rocq-upstream-runtime-20260908
export PATH="/home/theo/.opam/rocq93_native/bin:/usr/bin:/bin"
unset COQLIB ROCQLIB COQPATH ROCQPATH OCAMLPATH CAML_LD_LIBRARY_PATH
export CAML_LD_LIBRARY_PATH=/home/theo/.opam/rocq93_native/lib/stublibs
printf 'STAGE upstream OCaml runtime only (no Rocq workers)\n'
cd "$stock"
timeout --signal=TERM --kill-after=5s 600 dune build -j2 rocq-runtime.install \
  >"$task_dir/stock-runtime-only.log" 2>&1
printf 'STAGE exact branch OCaml plugin\n'
timeout --signal=TERM --kill-after=5s 90 bash "$repo_root/work/ndjson-pr67-20260909/plugin-check.sh" "$task_dir/source" \
  >"$task_dir/plugin-only.log" 2>&1
printf 'PASS exact branch OCaml plugin\n'
