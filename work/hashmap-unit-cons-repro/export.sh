#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
converter=$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py
cd -- "$repro_dir"
[[ ! -e HashMapCons.ndjson && ! -e HashMapCons.lean-export ]]
LEAN_PATH="$toolchain/lib/lean" "$exporter" Std.Data.HashMap.Lemmas -- \
  Std.HashMap.unitOfList_cons > HashMapCons.ndjson
ROCQLKA_NDJSON_STREAM=1 python3 "$converter" HashMapCons.ndjson HashMapCons.lean-export
wc -l -c HashMapCons.lean-export
sha256sum HashMapCons.lean-export
