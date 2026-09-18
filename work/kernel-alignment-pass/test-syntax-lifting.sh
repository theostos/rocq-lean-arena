#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/syntax-lifting.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
if [[ ${1:-candidate} == baseline ]]; then
  "${compiler[@]}" -c "$kernel_dir/test-suite/unit-tests/kernel/syntax_lifting.ml" \
    -o "$build_dir/syntax_lifting.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/syntax_lifting.cmx" -o "$build_dir/test.exe"
else
  "${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/constr.ml" \
    -o "$build_dir/reviewed_constr.cmx"
  "${compiler[@]}" -I "$build_dir" -c "$test_dir/lifting_prelude.ml" \
    -o "$build_dir/lifting_prelude.cmx"
  "${compiler[@]}" -I "$build_dir" -open Lifting_prelude \
    -c "$kernel_dir/test-suite/unit-tests/kernel/syntax_lifting.ml" \
    -o "$build_dir/syntax_lifting.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/reviewed_constr.cmx" \
    "$build_dir/lifting_prelude.cmx" "$build_dir/syntax_lifting.cmx" \
    -o "$build_dir/test.exe"
fi
timeout --kill-after=2s 10s "$build_dir/test.exe"
