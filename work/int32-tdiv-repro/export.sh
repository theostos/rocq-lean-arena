#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
export LEAN_SYSROOT="$toolchain"
export LEAN_PATH="$toolchain/lib/lean"
cd -- "$repro_dir"

# Export the existing theorem and its dependencies, without rewriting its proof.
"$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export" \
  Init.Data.SInt.Lemmas -- Int32.ofInt_tdiv > Int32Tdiv.ndjson
ROCQLKA_NDJSON_STREAM=1 python3 \
  "$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py" \
  Int32Tdiv.ndjson Int32Tdiv.lean-export
wc -l -c Int32Tdiv.ndjson Int32Tdiv.lean-export
sha256sum Int32Tdiv.ndjson Int32Tdiv.lean-export
