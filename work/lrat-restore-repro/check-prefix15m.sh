#!/usr/bin/env bash
# Explicit compatibility check for the saved 15M prefix, without rewriting its seal.
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
cd -- "$repo_dir"
run_dir=$repo_dir/work/cslib-full-fresh/runs/cslib-unit-fix
seal=$run_dir/Prefix15M.seal
bash "$repo_dir/work/unit-projection-repro/check-toolchain.sh"
digest=$(sha256sum "$seal/inputs.sha256" | awk '{print $1}')
if [[ $digest == 77e16b17b8c8bc0477074f2c4cf65a9ef2a7ec01b634c26f526aab96410f5279 ]]; then
  # This exact historical seal used worker d9710716. Only the worker and two
  # launch/check scripts changed. Every proof input and checkpoint source must
  # still match. The new worker is pinned by check-toolchain.sh above.
  sha256sum --check --strict <<'EXPECTED'
756cd331b222276a1d95a98394f14165841ae0561160a9000ef29f8284f7dd18  work/cslib-full-fresh/runs/cslib-unit-fix/Prefix15M.seal/artifact.sha256
EXPECTED
  awk -v worker="$repo_dir/_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe" \
      -v launcher="$repo_dir/work/uint32-not-repro/resume-cslib.sh" \
      -v checker="$repo_dir/work/unit-projection-repro/check-toolchain.sh" \
      '$2 != worker && $2 != launcher && $2 != checker {print}' \
      "$seal/inputs.sha256" | sha256sum --check --strict
else
  # A checkpoint produced by the current launcher needs no migration.
  sha256sum --check --strict "$seal/inputs.sha256"
fi
sha256sum --check --strict "$seal/artifact.sha256"
echo 'Verified unchanged 15M checkpoint for the pinned current kernel.'
