#!/usr/bin/env bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
helper_src=$test_dir/dag-context-experiment
build_dir=$(mktemp -d -- "$test_dir/.constr-equal-build.XXXXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT

compiler=(/home/theo/.opam/rocq93_native/bin/ocamlfind ocamlopt
  -rectypes -thread -package rocq-runtime.vernac -I "$build_dir")
"${compiler[@]}" -c "$helper_src/leanConstr.mli" -o "$build_dir/leanConstr.cmi"
"${compiler[@]}" -c "$helper_src/leanConstr.ml" -o "$build_dir/leanConstr.cmx"
"${compiler[@]}" -c "$test_dir/test_constr_equal.ml" -o "$build_dir/test_constr_equal.cmx"
"${compiler[@]}" -linkpkg "$build_dir/leanConstr.cmx" \
  "$build_dir/test_constr_equal.cmx" -o "$build_dir/test_constr_equal.exe"
"$build_dir/test_constr_equal.exe"
