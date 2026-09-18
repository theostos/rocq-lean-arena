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
export ROCQ_MAX_RSS_KIB=3932160 ROCQ_MEMORY_MAX_KIB=4194304
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
export ROCQ_STACK_KIB=262144 ROCQ_MEMORY_POLL_SECONDS=0.25
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0
export ROCQ_CHECKPOINT_LOG_FILE=$repro_dir/$test_name.$run_tag.run.log
exec bash "$repo_dir/work/run-checkpoint-atomic.sh" "$repro_dir/$test_name.v" -- \
  timeout --signal=TERM --kill-after=5s 600 \
  "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c -q \
  -bytecode-compiler no \
  -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
  -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
  -Q "$repro_dir" '' \
  -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
  > "$repro_dir/$test_name.$run_tag.guard.log" 2>&1
