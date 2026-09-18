#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
toolchain=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
converter=$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py
cd -- "$repro_dir"
[[ $(sha256sum "$exporter" | cut -d ' ' -f 1) == d259b6dd65008ba89e36c866a514b8996f093ed4f605c8b6efd1b2e014cbf393 ]]
[[ $(sha256sum "$converter" | cut -d ' ' -f 1) == fff4aa5d44ed71a69019be02ae5eddfcc226308ca057788b30ad81d9df89e0e0 ]]
[[ ! -e Target.ndjson && ! -e Target.lean-export ]]
"$toolchain/bin/lean" --version
LEAN_PATH="$toolchain/lib/lean" "$exporter" \
  Std.Tactic.BVDecide.Bitblast.BVExpr.Circuit.Lemmas.Operations.Add -- \
  Std.Tactic.BVDecide.BVExpr.bitblast.blastAdd.go_denote_eq \
  > Target.ndjson
ROCQLKA_NDJSON_STREAM=1 python3 "$converter" Target.ndjson Target.lean-export
wc -l -c Target.lean-export
sha256sum Target.ndjson Target.lean-export
