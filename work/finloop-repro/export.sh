#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
lean_bin=/home/theo/.elan/toolchains/leanprover--lean4---v4.27.0-rc1/bin
exporter=$repo_dir/_deps/lean-kernel-arena/_build/lean4export/leanprover_lean4_v4.27.0-rc1/.lake/build/bin/lean4export
cd -- "$repo_dir/_deps/lean-kernel-arena/_build/tests/work/cslib/src"
# Keep the original library proof; only restrict the export to its dependencies.
"$lean_bin/lake" env "$exporter" Cslib.Computability.Automata.NA.Loop -- \
  Cslib.Automata.NA.FinAcc.instTotalSumUnitFinLoopOfNonemptyElemStart \
  > "$repro_dir/FinLoop.ndjson"
ROCQLKA_NDJSON_STREAM=1 python3 \
  "$repo_dir/_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py" \
  "$repro_dir/FinLoop.ndjson" "$repro_dir/FinLoop.lean-export"
wc -l -c "$repro_dir/FinLoop.lean-export"
sha256sum "$repro_dir/FinLoop.lean-export"
