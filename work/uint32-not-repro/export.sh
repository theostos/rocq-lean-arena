#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
converter=$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py
cd -- "$repro_dir"
export_name=${1:-UIntNot}
if (( $# > 0 )); then shift; fi
[[ $export_name =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || exit 64
declarations=("$@")
if (( ${#declarations[@]} == 0 )); then declarations=(UInt32.toInt32_not); fi
[[ ! -e $export_name.ndjson && ! -e $export_name.lean-export ]]
LEAN_PATH="$toolchain/lib/lean" "$exporter" Init.Data.SInt.Bitwise -- \
  "${declarations[@]}" > "$export_name.ndjson"
ROCQLKA_NDJSON_STREAM=1 python3 "$converter" "$export_name.ndjson" "$export_name.lean-export"
wc -l -c "$export_name.lean-export"
sha256sum "$export_name.lean-export"
