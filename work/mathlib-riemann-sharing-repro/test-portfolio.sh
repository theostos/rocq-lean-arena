#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
shared_tests=$repo_dir/work/kernel-alignment-pass
build_dir=$(mktemp -d -- "$test_dir/portfolio-tests.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$test_dir/conversion.portfolio.ml" \
  -o "$build_dir/reviewed_conversion.cmx"
"${compiler[@]}" -I "$build_dir" -c "$shared_tests/witness_prelude.ml" \
  -o "$build_dir/witness_prelude.cmx"
for name in unit_type_witness unit_case_witness; do
  "${compiler[@]}" -I "$build_dir" -open Witness_prelude \
    -c "$kernel_dir/test-suite/unit-tests/kernel/$name.ml" -o "$build_dir/$name.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
    "$build_dir/witness_prelude.cmx" "$build_dir/$name.cmx" -o "$build_dir/$name.exe"
  timeout --kill-after=2s 20s "$build_dir/$name.exe"
done
for source in "$shared_tests/conversion_schedule_test.ml" \
  "$shared_tests/projection_unit_witness.ml" "$shared_tests/projection_cache_test.ml" \
  "$shared_tests/quotation_budget_test.ml" "$shared_tests/unfolding_order_test.ml" \
  "$shared_tests/deferred_witness_test.ml" "$shared_tests/unit_type_shift_test.ml" \
  "$shared_tests/conversion_retry_test.ml"; do
  name=$(basename -- "$source" .ml)
  "${compiler[@]}" -I "$build_dir" -c "$source" -o "$build_dir/$name.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
    "$build_dir/$name.cmx" -o "$build_dir/$name.exe"
  timeout --kill-after=2s 20s "$build_dir/$name.exe"
done
printf '%s\n' "All isolated candidate tests passed: $build_dir"
