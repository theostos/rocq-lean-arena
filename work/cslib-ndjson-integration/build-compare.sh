#!/usr/bin/env bash
set -Eeuo pipefail
task=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
root=$(cd -- "$task/../.." && pwd -P)
src=$root/_worktrees/rocq-lean-import/cslib-ndjson/src
prefix=$root/_worktrees/rocq/compact-peano-view/_build/install/default
export OCAMLPATH="$prefix/lib:$src/../_build/findlib"
compiler=(/home/theo/.opam/rocq93_native/bin/ocamlfind ocamlopt
  -rectypes -thread -package rocq-runtime.vernac,yojson -I "$task" -I "$src")
objects=()
for module in leanName leanParseShared leanParse leanParseNdjson; do
  "${compiler[@]}" -c "$src/$module.ml" -o "$task/$module.cmx"
  objects+=("$task/$module.cmx")
done
"${compiler[@]}" -c "$task/compare.ml" -o "$task/compare.cmx"
"${compiler[@]}" -linkpkg "${objects[@]}" "$task/compare.cmx" -o "$task/compare.exe"
