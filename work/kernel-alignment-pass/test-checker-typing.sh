#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/checker-typing.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.checklib -open Coq_checklib)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/checker/mod_checking.ml" \
  -o "$build_dir/reviewed_mod_checking.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/checker_typing_test.ml" \
  -o "$build_dir/checker_typing_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_mod_checking.cmx" \
  "$build_dir/checker_typing_test.cmx" -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
