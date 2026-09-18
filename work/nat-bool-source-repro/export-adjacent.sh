#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
converter=$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py
cd -- "$repro_dir"
[[ ! -e Adjacent.ndjson && ! -e Adjacent.lean-export ]]
LEAN_PATH="$toolchain/lib/lean" "$exporter" Init.Data.Nat.Basic -- \
  Nat.beq_refl Nat.beq_eq Nat.ble_eq Nat.blt_eq > Adjacent.ndjson
ROCQLKA_NDJSON_STREAM=1 python3 "$converter" Adjacent.ndjson Adjacent.lean-export
wc -l -c Adjacent.lean-export
sha256sum Adjacent.lean-export
