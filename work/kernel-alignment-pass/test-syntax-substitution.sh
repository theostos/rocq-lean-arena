#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/syntax-substitution.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
if [[ ${1:-candidate} == baseline ]]; then
  "${compiler[@]}" -c "$kernel_dir/test-suite/unit-tests/kernel/syntax_substitution.ml" \
    -o "$build_dir/syntax_substitution.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/syntax_substitution.cmx" -o "$build_dir/test.exe"
else
  "${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/vars.ml" \
    -o "$build_dir/reviewed_vars.cmx"
  "${compiler[@]}" -I "$build_dir" -c "$test_dir/substitution_prelude.ml" \
    -o "$build_dir/substitution_prelude.cmx"
  "${compiler[@]}" -I "$build_dir" -open Substitution_prelude \
    -c "$kernel_dir/test-suite/unit-tests/kernel/syntax_substitution.ml" \
    -o "$build_dir/syntax_substitution.cmx"
  "${compiler[@]}" -linkpkg "$build_dir/reviewed_vars.cmx" \
    "$build_dir/substitution_prelude.cmx" "$build_dir/syntax_substitution.cmx" \
    -o "$build_dir/test.exe"
fi
if [[ -n ${2:-} ]]; then
  timeout --kill-after=2s 10s "$build_dir/test.exe" "$2"
else
  timeout --kill-after=2s 10s "$build_dir/test.exe"
fi
