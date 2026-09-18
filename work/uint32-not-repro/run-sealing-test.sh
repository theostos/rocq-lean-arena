#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
run_tag=${1:?Usage: run-sealing-test.sh UNIQUE_TAG}
[[ $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
manifest=$repro_dir/sealing.$run_tag.sha256
[[ ! -e $manifest ]] || exit 64
sha256sum "$repo_dir/_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe" \
  "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src/lean_import.cmxs" \
  "$repo_dir/work/int32-tdiv-repro/foundation/Lean.vo" \
  "$repro_dir/UIntNot.lean-export" "$repro_dir/Prefix.vo" > "$manifest"
ROCQ_CHECKPOINT_INPUTS_FILE="$manifest" bash "$repro_dir/run.sh" Checkpoint "$run_tag"
ROCQ_CHECKPOINT_INPUTS_FILE="$manifest" bash "$repro_dir/run.sh" Checkpoint "$run_tag-reuse"
bash "$repro_dir/run.sh" AfterCheckpoint "$run_tag"
bash "$repro_dir/run.sh" ReloadCheckpoint "$run_tag"
echo 'PASS checkpoint creation, verified reuse, continuation and fresh reload'
