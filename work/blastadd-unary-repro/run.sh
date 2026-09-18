#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
test_name=${1:?Usage: run.sh TEST_NAME UNIQUE_TAG}
run_tag=${2:?Usage: run.sh TEST_NAME UNIQUE_TAG}
[[ $test_name =~ ^[A-Za-z][A-Za-z0-9_]*$ && $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
run_dir=$repro_dir/$run_tag
if [[ ${3:-} != --inside ]]; then
  [[ ! -e $run_dir ]] || exit 64
  mkdir -p "$run_dir/foundation"
  cp "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src/Lean.v" "$run_dir/foundation/Lean.v"
  cp "$repro_dir/$test_name.v" "$run_dir/$test_name.v"
  ln -s "$repro_dir/Target.lean-export" "$run_dir/Target.lean-export"
  export ROCQ_MAX_RSS_KIB=3932160 ROCQ_MEMORY_MAX_KIB=4194304
  export ROCQ_MEMORY_HIGH_KIB=4194304 ROCQ_ALLOW_EXTERNAL_ROCQ=0
  export ROCQ_MIN_AVAILABLE_KIB=3145728 ROCQ_MEMORY_SWAP_MAX_KIB=0
  export ROCQ_STACK_KIB=8192 ROCQ_MEMORY_POLL_SECONDS=0.25
  export ROCQ_MEMORY_STATUS_SECONDS=60
  export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0,b
  exec bash "$repo_dir/work/run-memory-guarded.sh" \
    timeout --signal=TERM --kill-after=5s 600 \
    bash "$repro_dir/run.sh" "$test_name" "$run_tag" --inside \
    > "$run_dir/guard.log" 2>&1
fi
[[ ${_ROCQ_MEMORY_GUARD_SCOPED:-} == 1 ]] || exit 64
kernel=$repo_dir/_worktrees/rocq/compact-peano-view
compiler=("$kernel/_build/default/topbin/rocqworker.exe")
if [[ ${ROCQ_TEST_BASELINE:-0} == 1 ]]; then
  compiler=("$repro_dir/rocqworker.baseline.exe")
fi
common=(--kind=compile -coqlib "$kernel/_build/install/default/lib/coq" -q
  -bytecode-compiler no
  -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib
  -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src"
  -Q "$run_dir/foundation" LeanImport)
cd "$run_dir/foundation"
"${compiler[@]}" "${common[@]}" Lean.v > "$run_dir/foundation.log" 2>&1
cd "$run_dir"
if [[ ${ROCQ_TEST_GDB:-0} == 1 ]]; then
  breakpoints=()
  if [[ ${ROCQ_TEST_GDB_ASSERT:-0} == 1 ]]; then
    breakpoints=(-ex 'break kernel/cClosure.ml:872')
  fi
  exec gdb -q -batch -ex 'set pagination off' \
    -ex "directory $kernel" "${breakpoints[@]}" \
    -ex 'handle SIGALRM stop print pass' -ex run -ex 'bt 512' -ex continue \
    --args "${compiler[@]}" "${common[@]}" "$test_name.v" > "$run_dir/run.log" 2>&1
fi
"${compiler[@]}" "${common[@]}" "$test_name.v" > "$run_dir/run.log" 2>&1
