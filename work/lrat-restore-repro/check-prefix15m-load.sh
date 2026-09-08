#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
run_dir=$repo_dir/work/cslib-full-fresh/runs/cslib-unit-fix
run_tag=${1:?Usage: check-prefix15m-load.sh UNIQUE_TAG}
[[ $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
stage=Reload15M
if [[ ${2:-} == --through-target ]]; then
  stage=CheckLratRestore
elif (( $# != 1 )); then
  echo 'Usage: check-prefix15m-load.sh UNIQUE_TAG [--through-target]' >&2
  exit 64
fi
[[ ! -e $repro_dir/$stage.$run_tag.guard.log ]] || exit 64
bash "$repro_dir/check-prefix15m.sh"
export ROCQ_MAX_RSS_KIB=7864320 ROCQ_MEMORY_MAX_KIB=8388608
if [[ $stage == CheckLratRestore ]]; then
  export ROCQ_MAX_RSS_KIB=11534336 ROCQ_MEMORY_MAX_KIB=12582912
fi
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
export ROCQ_STACK_KIB=262144 ROCQ_MEMORY_POLL_SECONDS=0.25
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0
export ROCQ_CHECKPOINT_LOG_FILE=$repro_dir/$stage.$run_tag.run.log
bash "$repo_dir/work/run-checkpoint-atomic.sh" "$run_dir/$stage.v" -- \
  timeout --signal=TERM --kill-after=5s 600 \
  "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c -q \
  -bytecode-compiler no \
  -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
  -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
  -Q "$run_dir" '' -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
  > "$repro_dir/$stage.$run_tag.guard.log" 2>&1
bash "$repro_dir/check-prefix15m.sh"
