#!/usr/bin/env bash
set -euo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
build_dir=$(mktemp -d -- "$test_dir/.quotation-test.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/lib
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
# Compile the actual private helper, without changing the kernel's public CMI.
sed -n '/^open CErrors$/,/^open Esubst$/p; /^let small_reification remaining root =/,/^let transparent_inductive_after_applying/ { /^let transparent_inductive_after_applying/!p; }' \
  "$repo_dir/_worktrees/rocq/compact-peano-view/kernel/conversion.ml" > "$build_dir/quotation_guard.ml"
"${compiler[@]}" -c "$build_dir/quotation_guard.ml" -o "$build_dir/quotation_guard.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/quotation_guard_test.ml" -o "$build_dir/quotation_guard_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/quotation_guard.cmx" "$build_dir/quotation_guard_test.cmx" -o "$build_dir/test.exe"
"$build_dir/test.exe"
