#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/quotation-test.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
for test in closure_quotation closure_snapshot closure_inspection closure_lifting unit_type_witness constant_deps syntax_lifting syntax_substitution syntax_module_substitution; do
  "${compiler[@]}" -c "$kernel_dir/test-suite/unit-tests/kernel/$test.ml" \
    -o "$build_dir/$test.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/$test.cmx" -o "$build_dir/$test.exe"
  timeout --kill-after=2s 10s "$build_dir/$test.exe"
done
