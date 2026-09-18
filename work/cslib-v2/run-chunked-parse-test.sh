#!/usr/bin/env bash
set -Eeuo pipefail

# Run through ../run-memory-guarded.sh, in the importer's OCaml environment.
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
parser_src=$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src
build_dir=$(mktemp -d -- "$test_dir/.chunk-parser-build.XXXXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT

# The installed .cmx files were built with -for-pack Lean_import. Compile the
# same parser sources without packing, using their existing public interfaces.
# This keeps the standalone test independent of plugin initialization.
compiler=(/home/theo/.opam/rocq93_native/bin/ocamlfind ocamlopt
  -rectypes -thread -package rocq-runtime.vernac
  -I "$build_dir" -I "$parser_src")
"${compiler[@]}" -c "$parser_src/leanName.ml" -o "$build_dir/leanName.cmx"
"${compiler[@]}" -c "$parser_src/leanParse.ml" -o "$build_dir/leanParse.cmx"
"${compiler[@]}" -c "$test_dir/test_chunked_parse.ml" -o "$build_dir/test_chunked_parse.cmx"
"${compiler[@]}" -linkpkg "$build_dir/leanName.cmx" "$build_dir/leanParse.cmx" \
  "$build_dir/test_chunked_parse.cmx" -o "$build_dir/test_chunked_parse.exe"
"$build_dir/test_chunked_parse.exe"
