#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
export LEAN_SYSROOT="$toolchain"
export LEAN_PATH="$repro_dir:$toolchain/lib/lean"
cd -- "$repro_dir"
"$toolchain/bin/lean" -o ConstructorOwner.olean ConstructorOwner.lean
"$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export" \
  ConstructorOwner -- repro > ConstructorOwner.ndjson
python3 "$repo_dir/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py" \
  ConstructorOwner.ndjson ConstructorOwner.lean-export
