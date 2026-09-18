#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
saved_dir=$(realpath -e -- "$1")
case "$saved_dir" in "$test_dir"/witness-candidate.*) ;; *) exit 2 ;; esac
test -f "$saved_dir/reviewed_conversion.cmx"
build_dir=$(mktemp -d -- "$test_dir/projection-witness.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -I "$saved_dir" -c "$test_dir/projection_unit_witness.ml" \
  -o "$build_dir/projection_unit_witness.cmx"
"${compiler[@]}" -linkpkg "$saved_dir/reviewed_conversion.cmx" \
  "$build_dir/projection_unit_witness.cmx" -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
