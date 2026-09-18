#!/usr/bin/env bash
set -Eeuo pipefail

repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
converter=$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py
cd -- "$repro_dir"

# Refuse changed tools or overwriting an earlier reproduction.
[[ $(sha256sum "$exporter" | cut -d ' ' -f 1) == d259b6dd65008ba89e36c866a514b8996f093ed4f605c8b6efd1b2e014cbf393 ]]
[[ $(sha256sum "$converter" | cut -d ' ' -f 1) == fff4aa5d44ed71a69019be02ae5eddfcc226308ca057788b30ad81d9df89e0e0 ]]
for export_name in Target Adjacent; do
  [[ ! -e $export_name.ndjson && ! -e $export_name.lean-export ]]
done
"$toolchain/bin/lean" --version

export_declarations() {
  local export_name=$1
  shift
  printf 'Exporting %s from Init.Data.SInt.Bitwise:' "$export_name"
  printf ' %s' "$@"
  printf '\n'
  LEAN_PATH="$toolchain/lib/lean" "$exporter" Init.Data.SInt.Bitwise -- \
    "$@" > "$export_name.ndjson"
  ROCQLKA_NDJSON_STREAM=1 python3 "$converter" "$export_name.ndjson" "$export_name.lean-export"
  wc -l -c "$export_name.lean-export"
  sha256sum "$export_name.ndjson" "$export_name.lean-export"
}

export_declarations Target Int8.toBitVec_not
export_declarations Adjacent \
  Int16.toBitVec_not Int32.toBitVec_not Int64.toBitVec_not ISize.toBitVec_not \
  Int8.toBitVec_and Int8.toBitVec_or Int8.toBitVec_xor
