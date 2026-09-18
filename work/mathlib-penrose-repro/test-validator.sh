#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/validator-unit.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.checklib -open Coq_checklib)
"${compiler[@]}" -w -4 -c "$test_dir/baseline_validate.ml" -o "$build_dir/baseline_validate.cmx"
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/checker/validate.ml" -o "$build_dir/reviewed_validate.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/validator_test.ml" -o "$build_dir/test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/baseline_validate.cmx" "$build_dir/reviewed_validate.cmx" \
  "$build_dir/test.cmx" -o "$build_dir/test.exe"
export ROCQ_MAX_RSS_KIB=3670016 ROCQ_MEMORY_MAX_KIB=4194304
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
exec bash "$repo_dir/work/run-memory-guarded.sh" timeout --kill-after=2s 120s "$build_dir/test.exe"
