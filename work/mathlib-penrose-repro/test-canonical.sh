#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/canonical-unit.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/constr.ml" \
  -o "$build_dir/reviewed_constr.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/canonical_test.ml" -o "$build_dir/canonical_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_constr.cmx" "$build_dir/canonical_test.cmx" \
  -o "$build_dir/test.exe"
timeout --kill-after=2s 20s "$build_dir/test.exe"
