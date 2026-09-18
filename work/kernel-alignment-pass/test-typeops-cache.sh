#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
build_dir=$(mktemp -d -- "$test_dir/typeops-cache.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel_dir/_build/install/default/lib
ulimit -v 1048576
compiler=(ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel)
"${compiler[@]}" -w -4 -intf-suffix .disabled -c "$kernel_dir/kernel/typeops.ml" \
  -o "$build_dir/reviewed_typeops.cmx"
"${compiler[@]}" -I "$build_dir" -c "$test_dir/typeops_cache_test.ml" \
  -o "$build_dir/typeops_cache_test.cmx"
"${compiler[@]}" -linkpkg "$build_dir/reviewed_typeops.cmx" \
  "$build_dir/typeops_cache_test.cmx" -o "$build_dir/test.exe"
timeout --kill-after=2s 10s "$build_dir/test.exe"
