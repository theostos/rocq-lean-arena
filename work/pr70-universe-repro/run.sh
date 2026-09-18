#!/usr/bin/env bash
# Reproduce the PR regression or the separate historical CSLib failure.
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
variant=${1:?usage: run.sh VARIANT [universes|int64]}
case "$variant" in
  before) commit=38fb4791bc7a3bc49995526448778c6e5555aaf1 ;;
  after) commit=2dc7529e2c9a9f999d944ae8495474a6503246df ;;
  historical-before) commit=ba22a2d21f89d57d6d02e062d5d2f026fb7d337d ;;
  historical-after) commit=4de13e203338e424980d055f8a6d38dcd57eeb41 ;;
  *) echo "Unknown variant: $variant" >&2; exit 64 ;;
esac
test_name=${2:-universes}
case "$test_name" in
  universes) source_name=UniverseInstances; input=universe_instances ;;
  int64) source_name=Int64; input=Int64.lean-export ;;
  *) echo "Unknown test: $test_name" >&2; exit 64 ;;
esac
importer="$repo_dir/_worktrees/rocq-lean-import/pr70-$variant"
if [[ ! -d "$importer" ]]; then
  git -C "$repo_dir/_deps/rocq-lean-import" worktree add --detach "$importer" "$commit"
fi
[[ $(git -C "$importer" rev-parse HEAD) == "$commit" ]]
git -C "$importer" diff --exit-code HEAD -- src
switch=${ROCQLKA_OPAM_SWITCH:-rocq93_clean}
run_dir=$(mktemp -d "$repro_dir/run-$variant-$test_name.XXXXXXXX")
printf 'Logs: %s\n' "$run_dir"
printf '%s\n' "$commit" > "$run_dir/importer-commit.txt"
sha256sum "$repro_dir/$input" > "$run_dir/input.sha256"
ROCQLKA_OPAM_SWITCH="$switch" ROCQLKA_IMPORTER_ROOT="$importer" \
  "$repo_dir/checkers/rocq-lean-import/scripts/build.sh" > "$run_dir/build.log" 2>&1
cd -- "$repro_dir"
set +e
"$repo_dir/checkers/rocq-lean-import/scripts/run-memory-guarded.sh" \
  opam exec --switch="$switch" -- timeout 60 \
  rocq compile -q -I "$importer/src" -Q "$importer/src" LeanImport \
  -o "$run_dir/$source_name.vo" "$repro_dir/$source_name.v" \
  > "$run_dir/result.log" 2>&1
status=$?
set -e
printf '%s\n' "$status" > "$run_dir/exit-status.txt"
tail -25 "$run_dir/result.log"
exit "$status"
