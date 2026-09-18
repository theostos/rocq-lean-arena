#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
support_dir=$repo_dir/work/kernel-alignment-pass
build_dir=$(mktemp -d -- "$test_dir/candidate.XXXXXXXX")
printf '%s\n' "$build_dir"
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/cClosure.ml" \
  -o "$build_dir/reviewed_closure.cmx"
"${compiler[@]}" -I "$build_dir" -c "$support_dir/closure_prelude.ml" \
  -o "$build_dir/closure_prelude.cmx"
"${compiler[@]}" -w -4 -I "$build_dir" -open Closure_prelude \
  -intf-suffix .disabled -c "$kernel_dir/kernel/conversion.ml" \
  -o "$build_dir/reviewed_conversion.cmx"
"${compiler[@]}" -I "$build_dir" -c "$support_dir/witness_prelude.ml" \
  -o "$build_dir/witness_prelude.cmx"
for test in unit_type_witness unit_case_witness; do
  "${compiler[@]}" -I "$build_dir" -open Closure_prelude -open Witness_prelude \
    -c "$kernel_dir/test-suite/unit-tests/kernel/$test.ml" -o "$build_dir/$test.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/reviewed_closure.cmx" \
    "$build_dir/closure_prelude.cmx" "$build_dir/reviewed_conversion.cmx" \
    "$build_dir/witness_prelude.cmx" "$build_dir/$test.cmx" -o "$build_dir/$test.exe"
  timeout --kill-after=2s 10s "$build_dir/$test.exe"
done
