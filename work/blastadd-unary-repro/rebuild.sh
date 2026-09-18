#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
kernel=$repo_dir/_worktrees/rocq/compact-peano-view
export PATH=$kernel/_build/install/default/bin:/home/theo/.opam/rocq93_native/bin:$PATH
export OCAMLPATH=$kernel/_build/install/default/lib
export COQBIN=$kernel/_build/install/default/bin/
if [[ ${1:-} != --inside ]]; then
  export ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152
  export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
  exec bash "$repo_dir/work/run-memory-guarded.sh" \
    timeout --signal=TERM --kill-after=5s 900 bash "$0" --inside
fi
[[ ${_ROCQ_MEMORY_GUARD_SCOPED:-} == 1 ]] || exit 64
dune build --root "$kernel" -j1 rocq-runtime.install rocq-core.install
make -C "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current" \
  -B -f Makefile.rocq -j1 src/lean_import.cmxs
make -C "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" \
  -f Makefile.coq -j1 ZArith/BinInt.vo NArith/BinNat.vo NArith/Nnat.vo \
  ZArith/Znat.vo micromega/Lia.vo micromega/ZifyBool.vo
