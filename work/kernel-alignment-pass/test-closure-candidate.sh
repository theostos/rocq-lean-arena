#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/closure-candidate.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/cClosure.ml" \
  -o "$build_dir/reviewed_closure.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/closure_prelude.ml" \
  -o "$build_dir/closure_prelude.cmx"
for test in closure_lifting closure_quotation closure_snapshot closure_inspection; do
  "${compiler[@]}" -I "$build_dir" -open Closure_prelude \
    -c "$kernel_dir/test-suite/unit-tests/kernel/$test.ml" -o "$build_dir/$test.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/reviewed_closure.cmx" \
    "$build_dir/closure_prelude.cmx" "$build_dir/$test.cmx" -o "$build_dir/$test.exe"
  timeout --kill-after=2s 10s "$build_dir/$test.exe"
done
"${compiler[@]}" -I "$build_dir" -c "$test_dir/peano_quotation_cost_test.ml" \
  -o "$build_dir/peano_quotation_cost_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_closure.cmx" \
  "$build_dir/peano_quotation_cost_test.cmx" -o "$build_dir/peano-cost.exe"
timeout --kill-after=2s 10s "$build_dir/peano-cost.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/symbolic_views_test.ml" \
  -o "$build_dir/symbolic_views_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_closure.cmx" \
  "$build_dir/symbolic_views_test.cmx" -o "$build_dir/symbolic-views.exe"
timeout --kill-after=2s 20s "$build_dir/symbolic-views.exe"
