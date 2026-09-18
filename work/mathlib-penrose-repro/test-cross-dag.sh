#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
build_dir=$(mktemp -d -- "$test_dir/cross-dag-unit.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/lib
ulimit -v 1048576
ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel -c "$test_dir/cross_dag_test.ml" -o "$build_dir/test.cmx"
ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel -linkpkg "$build_dir/test.cmx" -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
