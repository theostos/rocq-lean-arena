#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
export LEAN_SYSROOT="$toolchain" LEAN_PATH="$repro_dir:$toolchain/lib/lean"
cd -- "$repro_dir"
"$toolchain/bin/lean" -o NullaryUnit.olean NullaryUnit.lean
"$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export" \
  NullaryUnit -- choose_eq chooseDep_eq unitMatch_eq unbox_eq bitValue_off bitValue_on indexedValue_eq \
  > NullaryUnit.ndjson
ROCQLKA_NDJSON_STREAM=1 python3 \
  "$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py" \
  NullaryUnit.ndjson NullaryUnit.lean-export
wc -l -c NullaryUnit.lean-export
