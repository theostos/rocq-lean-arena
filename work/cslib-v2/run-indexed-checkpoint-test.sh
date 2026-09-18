#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
parser_src=$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src
build_dir=$(mktemp -d -- "$test_dir/.indexed-checkpoint-build.XXXXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT
compiler=(/home/theo/.opam/rocq93_native/bin/ocamlfind ocamlopt
  -rectypes -thread -package rocq-runtime.vernac -I "$build_dir")
for module in leanName leanExpr leanParse; do
  "${compiler[@]}" -c "$parser_src/$module.mli" -o "$build_dir/$module.cmi"
  if [[ -f $parser_src/$module.ml ]]; then
    "${compiler[@]}" -c "$parser_src/$module.ml" -o "$build_dir/$module.cmx"
  fi
done
"${compiler[@]}" -c "$test_dir/test_indexed_checkpoint.ml" -o "$build_dir/test_indexed_checkpoint.cmx"
"${compiler[@]}" -linkpkg "$build_dir/leanName.cmx" "$build_dir/leanParse.cmx" \
  "$build_dir/test_indexed_checkpoint.cmx" -o "$build_dir/test_indexed_checkpoint.exe"
"$build_dir/test_indexed_checkpoint.exe"
