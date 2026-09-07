#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf '%s\n' "$*" >&2; exit 64; }
(( $# == 4 || $# == 5 )) || die 'Usage: run-checkpointed.sh EXPORT SHA256 SPLIT_LINE RUN_TAG [--resume]'
export_file=$(realpath -e -- "$1")
expected_export=$2
split_line=$3
run_tag=$4
mode=${5:-fresh}
[[ $expected_export =~ ^[0-9a-f]{64}$ && $split_line =~ ^[1-9][0-9]*$ ]] || die 'Invalid hash or split line'
[[ $run_tag =~ ^[A-Za-z0-9_-]+$ && ( $mode == fresh || $mode == --resume ) ]] || die 'Invalid tag or mode'
[[ $export_file != *'"'* && $export_file != *$'\n'* ]] || die 'Unsupported export filename'
run_base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$run_base/../.." && pwd -P)
run_dir=$run_base/runs/$run_tag
cd -- "$repo_dir"

# Only this tested experimental toolchain is supported. Never bypass digests.
sha256sum --check --strict <<'EXPECTED'
93b97317727e726c7b27b45c829536fba090085832e508b99fff4d8b3aafe4d0  _worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe
93f048367978e9d36bc8f79831eea0ce3b4dac5104297c843ffe95bfa13aec07  _worktrees/rocq-lean-import/compact-peano-importer-current/src/lean_import.cmxs
de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b  work/int32-tdiv-repro/foundation/Lean.vo
EXPECTED
printf '%s  %s\n' "$expected_export" "$export_file" | sha256sum --check --strict

if [[ $mode == fresh ]]; then
  mkdir -p -- "$run_base/runs"
  mkdir -- "$run_dir" || die 'Run directory exists; use another tag or --resume'
else
  [[ -s $run_dir/prefix.sha256 && -s $run_dir/inputs.sha256 ]] || die 'No validated prefix to resume'
fi
exec 9>"$run_dir/launcher.lock"
flock -n 9 || die 'This run already has an active launcher'
request=$(printf '%s\n%s\n%s' "$export_file" "$expected_export" "$split_line")
if [[ $mode == fresh ]]; then
  printf '%s\n' "$request" > "$run_dir/request.txt"
  for name in Prefix Complete; do
    cat > "$run_dir/$name.v" <<'PRELUDE'
From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 600.
PRELUDE
  done
  printf 'Lean Import "%s" 1 %s.\n' "$export_file" "$split_line" >> "$run_dir/Prefix.v"
  printf 'Require Import Prefix.\nLean Import "%s" %s.\n' "$export_file" "$split_line" >> "$run_dir/Complete.v"
  printf 'From LeanImport Require Import Lean.\nRequire Import Complete.\n' > "$run_dir/Reload.v"
  sha256sum "$export_file" \
    "$repo_dir/_worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe" \
    "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src/lean_import.cmxs" \
    "$repo_dir/work/int32-tdiv-repro/foundation/Lean.vo" \
    "$repo_dir/work/run-memory-guarded.sh" "$repo_dir/work/run-checkpoint-atomic.sh" \
    "$run_base/run-checkpointed.sh" \
    "$run_dir/Prefix.v" "$run_dir/Complete.v" "$run_dir/Reload.v" \
    > "$run_dir/inputs.sha256"
else
  [[ $(<"$run_dir/request.txt") == "$request" ]] || die 'Resume request does not match the saved prefix'
  sha256sum --check --strict "$run_dir/inputs.sha256" "$run_dir/prefix.sha256"
fi

attempt=$(mktemp -d -- "$run_dir/attempt.XXXXXXXX")
ln -sfn -- "$attempt" "$run_dir/latest"
for name in Prefix Complete Reload; do
  : > "$attempt/$name.run.log"
  : > "$attempt/$name.guard.log"
done
printf 'Logs: %s\n' "$attempt"
for name in "${!LEAN_IMPORT_@}" "${!ROCQ_DIAGNOSTIC_@}"; do
  [[ -z $name ]] || unset "$name"
done
export OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0
export ROCQ_MAX_RSS_KIB=${ROCQ_MAX_RSS_KIB:-15728640}
export ROCQ_MEMORY_MAX_KIB=${ROCQ_MEMORY_MAX_KIB:-16777216}
export ROCQ_MEMORY_HIGH_KIB=$ROCQ_MEMORY_MAX_KIB
export ROCQ_MIN_AVAILABLE_KIB=${ROCQ_MIN_AVAILABLE_KIB:-6291456}
export ROCQ_MEMORY_SWAP_MAX_KIB=0 ROCQ_STACK_KIB=262144
export ROCQ_ALLOW_EXTERNAL_ROCQ=0
export ROCQ_MEMORY_POLL_SECONDS=0.25 LEAN_IMPORT_CHECKPOINT_STATS=1
run_stage() {
  local name=$1
  printf 'Starting %s\n' "$name"
  ROCQ_CHECKPOINT_LOG_FILE="$attempt/$name.run.log" \
    bash "$repo_dir/work/run-checkpoint-atomic.sh" "$run_dir/$name.v" -- \
      timeout --signal=TERM --kill-after=5s 28800 \
      "$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" c -q \
      -bytecode-compiler no \
      -R "$repo_dir/_worktrees/rocq/stdlib-int32-repro/theories" Stdlib \
      -I "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
      -Q "$run_dir" '' -Q "$repo_dir/work/int32-tdiv-repro/foundation" LeanImport \
      > "$attempt/$name.guard.log" 2>&1
  sha256sum --check --strict "$run_dir/inputs.sha256"
  printf 'Passed %s\n' "$name"
}
if [[ $mode == fresh ]]; then
  run_stage Prefix
  sha256sum "$run_dir/Prefix.vo" "$run_dir/inputs.sha256" > "$run_dir/prefix.sha256"
fi
run_stage Complete
sha256sum --check --strict "$run_dir/prefix.sha256"
run_stage Reload
sha256sum "$run_dir/Prefix.vo" "$run_dir/Complete.vo" "$run_dir/Reload.vo" > "$attempt/artifacts.sha256"
printf 'Checking, saving and fresh reload passed. Logs: %s\n' "$attempt"
