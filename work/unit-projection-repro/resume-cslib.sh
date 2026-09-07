#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
run_dir=$repo_dir/work/cslib-full-fresh/runs/cslib-unit-fix

if (( $# == 0 )); then
  resume_stamp=$(date +%Y%m%dT%H%M%S%N)
  resume_unit=rocq-cslib-unit-projection-$resume_stamp.service
  service_log=$repro_dir/resume.$resume_stamp.service.log
  systemd-run --user --unit="$resume_unit" --service-type=exec \
    --property=TimeoutStopSec=45 --property=KillMode=control-group \
    --property="StandardOutput=append:$service_log" --property=StandardError=inherit \
    --working-directory="$repo_dir" \
    /usr/bin/env "ROCQ_MEMORY_OWNER_SERVICE=$resume_unit" \
    /usr/bin/bash "$repro_dir/resume-cslib.sh" --run
  printf 'Service: %s\nService log: %s\n' "$resume_unit" "$service_log"
  printf 'Watch: tail -n 5 -F %s/latest/*.log\n' "$run_dir"
  exit 0
fi
[[ $# == 1 && $1 == --run ]] || { echo 'Usage: resume-cslib.sh' >&2; exit 64; }

exec 9>"$run_dir/launcher.lock"
flock -n 9 || { echo 'This run already has an active launcher' >&2; exit 75; }
bash "$repro_dir/check-toolchain.sh"
attempt=$(mktemp -d -- "$run_dir/attempt.XXXXXXXX")
for stage in Complete Reload; do
  : > "$attempt/$stage.run.log"
  : > "$attempt/$stage.guard.log"
done
ln -sfn -- "$attempt" "$run_dir/latest"
printf 'Resuming the unchanged prefix at line 11005951 with unit-projection conversion.\nLogs: %s\n' "$attempt"

# Preserve both the historical prefix manifest and this attempt's actual inputs.
sha256sum "$repro_dir/check-toolchain.sh" "$repro_dir/resume-cslib.sh" \
  "$repo_dir/_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe" \
  "$run_dir/prefix.sha256" "$run_dir/inputs.sha256" > "$attempt/migration.sha256"
for name in "${!LEAN_IMPORT_@}" "${!ROCQ_DIAGNOSTIC_@}"; do
  [[ -z $name ]] || unset "$name"
done
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0
export ROCQ_MAX_RSS_KIB=15728640 ROCQ_MEMORY_MAX_KIB=16777216
export ROCQ_MEMORY_HIGH_KIB=16777216 ROCQ_MIN_AVAILABLE_KIB=3145728
export ROCQ_MEMORY_SWAP_MAX_KIB=0 ROCQ_STACK_KIB=262144
export ROCQ_ALLOW_EXTERNAL_ROCQ=0 ROCQ_MEMORY_POLL_SECONDS=0.25
export LEAN_IMPORT_CHECKPOINT_STATS=1
for stage in Complete Reload; do
  printf 'Starting %s\n' "$stage"
  ROCQ_CHECKPOINT_LOG_FILE="$attempt/$stage.run.log" \
    bash "$repo_dir/work/run-checkpoint-atomic.sh" "$run_dir/$stage.v" -- \
      timeout --signal=TERM --kill-after=5s 28800 \
      "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c -q \
      -bytecode-compiler no \
      -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
      -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
      -Q "$run_dir" '' -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
      > "$attempt/$stage.guard.log" 2>&1
  bash "$repro_dir/check-toolchain.sh"
  sha256sum --check --strict "$attempt/migration.sha256"
  printf 'Passed %s\n' "$stage"
done
sha256sum "$run_dir/Prefix.vo" "$run_dir/Complete.vo" "$run_dir/Reload.vo" \
  > "$attempt/artifacts.sha256"
printf 'Continuation, saving and fresh reload passed. Logs: %s\n' "$attempt"
