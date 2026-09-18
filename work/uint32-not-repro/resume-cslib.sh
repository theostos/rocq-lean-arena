#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
run_dir=$repo_dir/work/cslib-full-fresh/runs/cslib-unit-fix
mode=complete
internal=0
for arg in "$@"; do
  case $arg in
    --checkpoint-only) mode=checkpoint ;;
    --run) internal=1 ;;
    *) echo 'Usage: resume-cslib.sh [--checkpoint-only]' >&2; exit 64 ;;
  esac
done
if (( ! internal )); then
  resume_stamp=$(date +%Y%m%dT%H%M%S%N)
  resume_unit=rocq-cslib-15m-$resume_stamp.service
  service_log=$repro_dir/resume.$resume_stamp.service.log
  mode_args=()
  [[ $mode != checkpoint ]] || mode_args=(--checkpoint-only)
  systemd-run --user --unit="$resume_unit" --service-type=exec \
    --property=TimeoutStopSec=45 --property=KillMode=control-group \
    --property="StandardOutput=append:$service_log" --property=StandardError=inherit \
    --working-directory="$repo_dir" \
    /usr/bin/env "ROCQ_MEMORY_OWNER_SERVICE=$resume_unit" \
    /usr/bin/bash "$repro_dir/resume-cslib.sh" --run "${mode_args[@]}"
  printf 'Service: %s\nService log: %s\n' "$resume_unit" "$service_log"
  printf 'Watch: tail -n 5 -F %s/latest/*.log\n' "$run_dir"
  exit 0
fi
cd -- "$repo_dir"
exec 9>"$run_dir/launcher.lock"
flock -n 9 || { echo 'This run already has an active launcher' >&2; exit 75; }
bash "$repo_dir/work/unit-projection-repro/check-toolchain.sh"
attempt=$(mktemp -d -- "$run_dir/attempt.XXXXXXXX")
stages=(Prefix15M Reload15M)
[[ $mode == checkpoint ]] || stages+=(Complete15M ReloadComplete15M)
for stage in "${stages[@]}"; do
  : > "$attempt/$stage.run.log"
  : > "$attempt/$stage.guard.log"
done
ln -sfn -- "$attempt" "$run_dir/latest"
printf 'Target checkpoint: through line 15001015; continuation starts at 15001016.\nLogs: %s\n' "$attempt"

# The original prefix and its historical manifests remain unchanged.
# Record the exact current producer inputs, including the selected new worker.
awk '$2 !~ /\/topbin\/rocqworker.exe$/ { print }' "$run_dir/inputs.sha256" \
  > "$attempt/inputs.sha256"
cat "$run_dir/prefix.sha256" >> "$attempt/inputs.sha256"
sha256sum "$repro_dir/resume-cslib.sh" \
  "$repo_dir/work/unit-projection-repro/check-toolchain.sh" \
  "$repo_dir/work/lrat-restore-repro/check-prefix15m.sh" \
  "$repo_dir/work/run-sealed-checkpoint.sh" \
  "$repo_dir/_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe" \
  "$run_dir/Prefix15M.v" "$run_dir/Reload15M.v" \
  "$run_dir/Complete15M.v" "$run_dir/ReloadComplete15M.v" \
  >> "$attempt/inputs.sha256"
for name in "${!LEAN_IMPORT_@}" "${!ROCQ_DIAGNOSTIC_@}"; do
  [[ -z $name ]] || unset "$name"
done
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0
export ROCQ_MAX_RSS_KIB=15728640 ROCQ_MEMORY_MAX_KIB=16777216
export ROCQ_MEMORY_HIGH_KIB=16777216 ROCQ_MIN_AVAILABLE_KIB=3145728
export ROCQ_MEMORY_SWAP_MAX_KIB=0 ROCQ_STACK_KIB=262144
export ROCQ_ALLOW_EXTERNAL_ROCQ=0 ROCQ_MEMORY_POLL_SECONDS=0.25
export LEAN_IMPORT_CHECKPOINT_STATS=1
export ROCQ_CHECKPOINT_INPUTS_FILE=$attempt/inputs.sha256
for stage in "${stages[@]}"; do
  runner=$repo_dir/work/run-checkpoint-atomic.sh
  case $stage in
    Prefix15M|Complete15M) runner=$repo_dir/work/run-sealed-checkpoint.sh ;;
  esac
  if [[ $stage == Complete15M ]]; then
    cp "$attempt/inputs.sha256" "$attempt/complete-inputs.sha256"
    sha256sum "$run_dir/Prefix15M.vo" >> "$attempt/complete-inputs.sha256"
    export ROCQ_CHECKPOINT_INPUTS_FILE=$attempt/complete-inputs.sha256
  fi
  printf 'Starting %s\n' "$stage"
  if [[ $stage == Prefix15M && -d $run_dir/Prefix15M.seal ]]; then
    bash "$repo_dir/work/lrat-restore-repro/check-prefix15m.sh" \
      > "$attempt/$stage.guard.log" 2>&1
  else
    ROCQ_CHECKPOINT_LOG_FILE="$attempt/$stage.run.log" \
      bash "$runner" "$run_dir/$stage.v" -- \
        timeout --signal=TERM --kill-after=5s 28800 \
        "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c -q \
        -bytecode-compiler no \
        -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
        -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
        -Q "$run_dir" '' -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
        > "$attempt/$stage.guard.log" 2>&1
  fi
  sha256sum --check --strict "$attempt/inputs.sha256"
  printf 'Passed %s\n' "$stage"
done
printf 'Checkpoint saved and freshly reloaded. Next line: 15001016.\n'
if [[ $mode == complete ]]; then
  sha256sum "$run_dir/Complete15M.vo" "$run_dir/ReloadComplete15M.vo" \
    > "$attempt/artifacts.sha256"
  printf 'Full continuation, saving and fresh reload passed.\n'
fi
