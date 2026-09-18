#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
test_name=${1:?Usage: run.sh TEST_NAME UNIQUE_TAG}
run_tag=${2:?Usage: run.sh TEST_NAME UNIQUE_TAG}
[[ $test_name =~ ^[A-Za-z][A-Za-z0-9_]*$ && $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
for suffix in guard run; do
  [[ ! -e $repro_dir/$test_name.$run_tag.$suffix.log ]] || exit 64
done
export ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
export ROCQ_STACK_KIB=${ROCQ_TEST_STACK_KIB:-262144} ROCQ_MEMORY_POLL_SECONDS=0.25
export ROCQ_MEMORY_STATUS_SECONDS=60
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0,b
export ROCQ_CHECKPOINT_LOG_FILE=$repro_dir/$test_name.$run_tag.run.log
compiler=("$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c)
if [[ ${ROCQ_TEST_BASELINE:-0} == 1 ]]; then
  compiler=("$repro_dir/rocqworker.baseline.exe" --kind=compile
    -coqlib "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/lib/coq")
fi
runner=$repo_dir/work/run-checkpoint-atomic.sh
if [[ -n ${ROCQ_CHECKPOINT_INPUTS_FILE:-} ]]; then
  runner=$repo_dir/work/run-sealed-checkpoint.sh
fi
exec bash "$runner" "$repro_dir/$test_name.v" -- \
  timeout --signal=TERM --kill-after=5s 180 \
  "${compiler[@]}" -q \
  -bytecode-compiler no \
  -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
  -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
  -Q "$repro_dir" '' \
  -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
  > "$repro_dir/$test_name.$run_tag.guard.log" 2>&1
