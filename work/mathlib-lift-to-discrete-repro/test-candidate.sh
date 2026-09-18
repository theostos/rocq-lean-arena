#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/candidate.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/conversion.ml" \
  -o "$build_dir/reviewed_conversion.cmx"
"${compiler[@]}" -I "$build_dir" -c "$repo_dir/work/kernel-alignment-pass/witness_prelude.ml" \
  -o "$build_dir/witness_prelude.cmx"
"${compiler[@]}" -I "$build_dir" -open Witness_prelude \
  -c "$kernel_dir/test-suite/unit-tests/kernel/unit_case_witness.ml" \
  -o "$build_dir/unit_case_witness.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/witness_prelude.cmx" "$build_dir/unit_case_witness.cmx" -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
