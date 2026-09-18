#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/checker.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -g -rectypes -thread -package rocq-runtime.checklib -open Coq_checklib)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/checker/checkLibrary.ml" -o "$build_dir/diagnostic_library.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/diagnostic_main.ml" -o "$build_dir/diagnostic_main.cmx"
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/checker/mod_checking.ml" -o "$build_dir/reviewed_mod_checking.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/recheck.ml" -o "$build_dir/recheck.cmx"
"${compiler[@]}" -linkpkg "$build_dir/diagnostic_library.cmx" "$build_dir/diagnostic_main.cmx" \
  "$build_dir/reviewed_mod_checking.cmx" "$build_dir/recheck.cmx" -o "$build_dir/recheck.exe"
printf '%s\n' "$build_dir/recheck.exe"
