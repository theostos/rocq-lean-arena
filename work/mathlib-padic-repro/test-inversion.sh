#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/inversion-unit.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/conversion.ml" \
  -o "$build_dir/reviewed_conversion.cmx"
"${compiler[@]}" -I "$build_dir" -c "$repo_dir/work/kernel-alignment-pass/projected_major_test.ml" \
  -o "$build_dir/projected_major_test.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/inversion_control_test.ml" \
  -o "$build_dir/inversion_control_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" \
  "$build_dir/projected_major_test.cmx" "$build_dir/inversion_control_test.cmx" \
  -o "$build_dir/test.exe"
timeout --kill-after=2s 15s "$build_dir/test.exe"
