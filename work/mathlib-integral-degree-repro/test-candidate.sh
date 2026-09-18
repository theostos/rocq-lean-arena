#!/usr/bin/env bash
set -Eeuo pipefail
candidate_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
test_dir=$candidate_dir/../kernel-alignment-pass
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/witness-candidate.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$candidate_dir/${1:-candidate}-conversion.ml" \
  -o "$build_dir/reviewed_conversion.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/witness_prelude.ml" \
  -o "$build_dir/witness_prelude.cmx"
"${compiler[@]}" -I "$build_dir" -open Witness_prelude \
  -c "$kernel_dir/test-suite/unit-tests/kernel/unit_type_witness.ml" \
  -o "$build_dir/unit_type_witness.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/witness_prelude.cmx" "$build_dir/unit_type_witness.cmx" \
  -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
"${compiler[@]}" -I "$build_dir" -open Witness_prelude \
  -c "$kernel_dir/test-suite/unit-tests/kernel/unit_case_witness.ml" \
  -o "$build_dir/unit_case_witness.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/witness_prelude.cmx" "$build_dir/unit_case_witness.cmx" -o "$build_dir/unit-case.exe"
timeout --kill-after=2s 10s "$build_dir/unit-case.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/projection_unit_witness.ml" \
  -o "$build_dir/projection_unit_witness.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projection_unit_witness.cmx" -o "$build_dir/projection-unit.exe"
timeout --kill-after=2s 10s "$build_dir/projection-unit.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/projection_cache_test.ml" \
  -o "$build_dir/projection_cache_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projection_cache_test.cmx" -o "$build_dir/cache-test.exe"
timeout --kill-after=2s 10s "$build_dir/cache-test.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/quotation_budget_test.ml" \
  -o "$build_dir/quotation_budget_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/quotation_budget_test.cmx" -o "$build_dir/quotation-budget.exe"
timeout --kill-after=2s 10s "$build_dir/quotation-budget.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/unfolding_order_test.ml" \
  -o "$build_dir/unfolding_order_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/unfolding_order_test.cmx" -o "$build_dir/unfolding-order.exe"
timeout --kill-after=2s 10s "$build_dir/unfolding-order.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/deferred_witness_test.ml" \
  -o "$build_dir/deferred_witness_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/deferred_witness_test.cmx" -o "$build_dir/deferred-witness.exe"
timeout --kill-after=2s 10s "$build_dir/deferred-witness.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/unit_type_shift_test.ml" \
  -o "$build_dir/unit_type_shift_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/unit_type_shift_test.cmx" -o "$build_dir/unit-type-shift.exe"
timeout --kill-after=2s 10s "$build_dir/unit-type-shift.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/type_query_sharing_test.ml" \
  -o "$build_dir/type_query_sharing_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/unit_type_shift_test.cmx" "$build_dir/type_query_sharing_test.cmx" \
  -o "$build_dir/type-query-sharing.exe"
timeout --kill-after=2s 10s "$build_dir/type-query-sharing.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/application_cache_test.ml" \
  -o "$build_dir/application_cache_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/application_cache_test.cmx" -o "$build_dir/application-cache.exe"
timeout --kill-after=2s 10s "$build_dir/application-cache.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/physical_conversion_test.ml" \
  -o "$build_dir/physical_conversion_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/physical_conversion_test.cmx" -o "$build_dir/physical-conversion.exe"
timeout --kill-after=2s 10s "$build_dir/physical-conversion.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/eliminator_head_test.ml" \
  -o "$build_dir/eliminator_head_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/eliminator_head_test.cmx" -o "$build_dir/eliminator-head.exe"
timeout --kill-after=2s 10s "$build_dir/eliminator-head.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/projected_major_test.ml" \
  -o "$build_dir/projected_major_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projected_major_test.cmx" -o "$build_dir/projected-major.exe"
timeout --kill-after=2s 10s "$build_dir/projected-major.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/projection_segments_test.ml" \
  -o "$build_dir/projection_segments_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projection_segments_test.cmx" -o "$build_dir/projection-segments.exe"
timeout --kill-after=2s 10s "$build_dir/projection-segments.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/projection_order_test.ml" \
  -o "$build_dir/projection_order_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projected_major_test.cmx" "$build_dir/projection_order_test.cmx" \
  -o "$build_dir/projection-order.exe"
timeout --kill-after=2s 10s "$build_dir/projection-order.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/projection_mismatched_fields_test.ml" \
  -o "$build_dir/projection_mismatched_fields_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projected_major_test.cmx" "$build_dir/projection_mismatched_fields_test.cmx" \
  -o "$build_dir/projection-mismatched-fields.exe"
timeout --kill-after=2s 10s "$build_dir/projection-mismatched-fields.exe"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/lazy_projection_test.ml" \
  -o "$build_dir/lazy_projection_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projected_major_test.cmx" "$build_dir/lazy_projection_test.cmx" \
  -o "$build_dir/lazy-projection.exe"
timeout --kill-after=2s 10s "$build_dir/lazy-projection.exe"
