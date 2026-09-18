#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
cd -- "$repo_dir/_deps/lean-kernel-arena/_build/tests/work/cslib/src"
"$toolchain/bin/lake" env "$exporter" Mathlib.LinearAlgebra.Span.Basic -- \
  LinearMap.exists_ne_zero_of_sSup_eq > "$repro_dir/LinearMap.ndjson"
ROCQLKA_NDJSON_STREAM=1 python3 \
  "$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py" \
  "$repro_dir/LinearMap.ndjson" "$repro_dir/LinearMap.lean-export"
wc -l -c "$repro_dir/LinearMap.lean-export"
