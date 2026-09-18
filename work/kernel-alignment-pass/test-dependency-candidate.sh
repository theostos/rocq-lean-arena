#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/dependency-candidate.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/environ.ml" \
  -o "$build_dir/reviewed_environ.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/dependency_prelude.ml" \
  -o "$build_dir/dependency_prelude.cmx"
"${compiler[@]}" -I "$build_dir" -open Dependency_prelude \
  -c "$kernel_dir/test-suite/unit-tests/kernel/constant_deps.ml" \
  -o "$build_dir/constant_deps.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_environ.cmx" \
  "$build_dir/dependency_prelude.cmx" "$build_dir/constant_deps.cmx" \
  -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
