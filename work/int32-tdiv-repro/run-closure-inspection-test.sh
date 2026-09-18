#!/usr/bin/env bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
build_dir=$(mktemp -d -- "$test_dir/.closure-inspection-build.XXXXXXXX")
trap 'rm -rf -- "$build_dir"' EXIT

compiler=(/home/theo/.opam/rocq93_native/bin/ocamlfind ocamlopt
  -rectypes -thread -package rocq-runtime.kernel)
source_file=$repo_dir/_worktrees/rocq/compact-peano-view/test-suite/unit-tests/kernel/closure_inspection.ml
"${compiler[@]}" -c "$source_file" -o "$build_dir/closure_inspection.cmx"
"${compiler[@]}" -linkpkg "$build_dir/closure_inspection.cmx" \
  -o "$build_dir/closure_inspection.exe"
"$build_dir/closure_inspection.exe"
