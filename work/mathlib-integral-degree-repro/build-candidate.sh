#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/checker.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1572864
compiler=(ocamlfind ocamlopt -g -rectypes -thread -package rocq-runtime.checklib -open Coq_checklib -I "$build_dir")
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$test_dir/$1-conversion.ml" -o "$build_dir/reviewed_conversion.cmx"
"${compiler[@]}" -w -4 -c "$test_dir/reviewed_typeops.ml" -o "$build_dir/reviewed_typeops.cmx"
"${compiler[@]}" -w -4 -c "$test_dir/reviewed_mod_checking.ml" -o "$build_dir/reviewed_mod_checking.cmx"
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/checker/checkLibrary.ml" -o "$build_dir/diagnostic_library.cmx"
"${compiler[@]}" -c "$test_dir/diagnostic_main.ml" -o "$build_dir/diagnostic_main.cmx"
"${compiler[@]}" -c "$test_dir/recheck.ml" -o "$build_dir/recheck.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_conversion.cmx" "$build_dir/reviewed_typeops.cmx" \
  "$build_dir/reviewed_mod_checking.cmx" "$build_dir/diagnostic_library.cmx" \
  "$build_dir/diagnostic_main.cmx" "$build_dir/recheck.cmx" -o "$build_dir/recheck.exe"
printf '%s\n' "$build_dir/recheck.exe"
