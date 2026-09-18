#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
converter=$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py
cd -- "$repro_dir"
LEAN_PATH="$repro_dir:$toolchain/lib/lean" "$toolchain/bin/lean" -o UnitProjection.olean UnitProjection.lean
LEAN_PATH="$repro_dir:$toolchain/lib/lean" "$exporter" UnitProjection -- \
  projected_identity two_projections nested_projection applied_projection > UnitProjection.ndjson
ROCQLKA_NDJSON_STREAM=1 python3 "$converter" UnitProjection.ndjson UnitProjection.lean-export
cd -- "$repo_dir/_deps/lean-kernel-arena/_build/tests/work/cslib/src"
"$toolchain/bin/lake" env "$exporter" Batteries.Control.LawfulMonadState -- \
  LawfulMonadStateOf.modify_eq > "$repro_dir/ModifyEq.ndjson"
ROCQLKA_NDJSON_STREAM=1 python3 "$converter" "$repro_dir/ModifyEq.ndjson" "$repro_dir/ModifyEq.lean-export"
wc -l -c "$repro_dir/UnitProjection.lean-export" "$repro_dir/ModifyEq.lean-export"
