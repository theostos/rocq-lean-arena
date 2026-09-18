#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
importer=$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current
run_tag=${1:-regression}
[[ $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
export ROCQ_MAX_RSS_KIB=3932160 ROCQ_MEMORY_MAX_KIB=4194304
export ROCQ_MIN_AVAILABLE_KIB=14155776 ROCQ_MEMORY_SWAP_MAX_KIB=0
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2
for test in nullary_unit_scheme primitive_record_eliminator rec_single_ctor \
  projection_relevance dependent_sprop_projection sprop_record_scheme \
  universe_instances mutual_inductives nested_containers nested_record_containers; do
  export ROCQ_CHECKPOINT_LOG_FILE=$repro_dir/$test.$run_tag.run.log
  [[ ! -e $ROCQ_CHECKPOINT_LOG_FILE ]] || exit 64
  bash "$repo_dir/work/run-checkpoint-atomic.sh" "$importer/tests/$test.v" -- \
    timeout --signal=TERM --kill-after=5s 600 \
    "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c -q \
    -bytecode-compiler no \
    -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
    -I "$importer/src" \
    -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
    > "$repro_dir/$test.$run_tag.guard.log" 2>&1
  printf 'PASS %s\n' "$test"
done
