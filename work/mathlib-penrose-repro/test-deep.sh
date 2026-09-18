#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
build_dir=$(mktemp -d -- "$test_dir/deep-unit.XXXXXXXX")
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/lib
ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel \
  -c "$test_dir/deep_test.ml" -o "$build_dir/deep_test.cmx"
ocamlfind ocamlopt -rectypes -thread -package rocq-runtime.kernel -linkpkg \
  "$build_dir/deep_test.cmx" -o "$build_dir/test.exe"
export ROCQ_MAX_RSS_KIB=3670016 ROCQ_MEMORY_MAX_KIB=4194304
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
# Three distinct traversals take about 89 CPU seconds together on this host.
# Leave scheduling margin; this is not the production declaration timeout.
exec bash "$repo_dir/work/run-memory-guarded.sh" timeout --kill-after=2s 120s \
  "$build_dir/test.exe" "${1:-3000000}"
