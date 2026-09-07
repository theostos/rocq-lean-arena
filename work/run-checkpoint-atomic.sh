#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run-checkpoint-atomic.sh CHECKPOINT.v -- ROCQ-COMMAND [ARG ...]

ROCQ-COMMAND must omit the checkpoint source, -o, and -output-directory.
The command is run through run-memory-guarded.sh.  Rocq writes all outputs to
a same-filesystem staging directory; CHECKPOINT.vo is atomically promoted only
after a zero exit status and a nonempty staged .vo.

Set ROCQ_CHECKPOINT_LOGICAL_DIR when CHECKPOINT.v belongs to a logical library
(for example, LeanImport or Stdlib.micromega).  The staging directory is then
mapped to that logical directory while Rocq writes the temporary .vo.

Set ROCQ_CHECKPOINT_LOG_FILE to an absolute path to retain the compiler output
outside the staging directory, including when compilation fails.
EOF
}

die() {
  printf 'checkpoint runner: %s\n' "$*" >&2
  exit 64
}

if [[ ${1:-} == --internal-promote ]]; then
  [[ ${_ROCQ_CHECKPOINT_INTERNAL:-0} == 1 ]] ||
    die "internal promotion mode may only be entered through the memory guard"
  (( $# >= 6 )) || die "invalid internal promotion invocation"
  shift
  source_dir=$1
  source_name=$2
  stage_dir=$3
  destination_vo=$4
  shift 4
  [[ $1 == -- ]] || die "invalid internal command separator"
  shift
  (( $# > 0 )) || die "missing internal Rocq command"

  checkpoint_name=${source_name%.v}
  [[ -d $source_dir && -f $source_dir/$source_name ]] || die "internal checkpoint source disappeared"
  [[ -d $stage_dir && $stage_dir == "$source_dir/.$checkpoint_name.stage."* ]] ||
    die "internal staging directory is outside the checkpoint directory"
  [[ $destination_vo == "$source_dir/$checkpoint_name.vo" ]] ||
    die "internal destination does not match the checkpoint source"
  stage_dev=$(stat -c %d -- "$stage_dir") || die "cannot inspect staging filesystem"
  destination_dev=$(stat -c %d -- "$source_dir") || die "cannot inspect destination filesystem"
  [[ $stage_dev == "$destination_dev" ]] || die "staging and destination are not on the same filesystem"

  source_hash_before=$(sha256sum -- "$source_dir/$source_name" | awk '{ print $1 }') ||
    die "cannot hash checkpoint source before compilation"
  stage_vo=$stage_dir/$checkpoint_name.vo
  logical_args=()
  if [[ -n ${ROCQ_CHECKPOINT_LOGICAL_DIR:-} ]]; then
    [[ $ROCQ_CHECKPOINT_LOGICAL_DIR =~ ^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$ ]] ||
      die "invalid ROCQ_CHECKPOINT_LOGICAL_DIR: $ROCQ_CHECKPOINT_LOGICAL_DIR"
    logical_args=(-Q "$stage_dir" "$ROCQ_CHECKPOINT_LOGICAL_DIR")
  fi

  log_file=${ROCQ_CHECKPOINT_LOG_FILE:-}
  if [[ -n $log_file ]]; then
    [[ $log_file == /* && $log_file != *$'\n'* ]] ||
      die "ROCQ_CHECKPOINT_LOG_FILE must be an absolute single-line path"
    log_parent=$(dirname -- "$log_file")
    [[ -d $log_parent && -w $log_parent ]] ||
      die "checkpoint log directory is unavailable: $log_parent"
    [[ $log_file != "$source_dir/$source_name" && $log_file != "$destination_vo" ]] ||
      die "checkpoint log must not overwrite the source or destination"
  fi

  rocq_command=("$@")
  run_rocq() (
    cd -- "$source_dir"
    # Keep importer serialization scratch files inside this transaction too:
    # the outer runner removes them even if the worker is killed by its cgroup.
    export LEAN_IMPORT_CHECKPOINT_TMP_DIR="$stage_dir"
    exec "${rocq_command[@]}" \
      "${logical_args[@]}" \
      -output-directory "$stage_dir" \
      -o "$stage_vo" \
      "$source_name"
  )

  if [[ -n $log_file ]]; then
    : >"$log_file" || die "cannot create checkpoint log: $log_file"
    if run_rocq >"$log_file" 2>&1; then
      command_status=0
    else
      command_status=$?
    fi
  elif run_rocq; then
    command_status=0
  else
    command_status=$?
  fi
  if (( command_status != 0 )); then
    printf 'checkpoint runner: command failed with status %s; canonical %s was not changed\n' \
      "$command_status" "$destination_vo" >&2
    exit "$command_status"
  fi
  [[ -f $stage_vo && -s $stage_vo ]] ||
    die "command succeeded without producing a nonempty staged $checkpoint_name.vo"
  source_hash_after=$(sha256sum -- "$source_dir/$source_name" | awk '{ print $1 }') ||
    die "cannot hash checkpoint source after compilation"
  [[ $source_hash_before == "$source_hash_after" ]] ||
    die "checkpoint source changed during compilation; refusing promotion"

  # This runs as the guarded workload, so the global heavyweight lock remains
  # held through the rename.  A second checkpoint cannot start in the gap
  # between compilation and publication.
  mv -fT -- "$stage_vo" "$destination_vo"
  printf 'checkpoint runner: atomically promoted %s\n' "$destination_vo" >&2
  exit 0
fi

if (( $# < 3 )) || [[ $2 != -- ]]; then
  usage
  exit 2
fi

source_arg=$1
shift 2
(( $# > 0 )) || die "missing Rocq command"

[[ -f $source_arg && $source_arg == *.v ]] || die "checkpoint source must be an existing .v file: $source_arg"
source_dir=$(cd -- "$(dirname -- "$source_arg")" && pwd -P) || die "cannot resolve checkpoint directory"
source_name=$(basename -- "$source_arg")
checkpoint_name=${source_name%.v}
[[ $checkpoint_name =~ ^[A-Za-z0-9_.-]+$ ]] || die "unsafe checkpoint basename: $checkpoint_name"

for arg in "$@"; do
  case $arg in
    -o|-o=*|-output-directory|-output-directory=*|--output-directory|--output-directory=*)
      die "the runner owns -o and -output-directory"
      ;;
  esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || die "cannot resolve runner directory"
guard=$script_dir/run-memory-guarded.sh
[[ -x $guard ]] || die "memory guard is missing or not executable: $guard"

# This lock covers staging plus promotion without leaving a lock artifact in
# the checkpoint directory.  The memory guard separately holds a user-wide
# lock while the heavyweight command itself is alive.
user_id=$(id -u)
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$user_id}
[[ -d $runtime_dir && -w $runtime_dir ]] || die "runtime directory is unavailable: $runtime_dir"
runtime_owner=$(stat -c %u -- "$runtime_dir") || die "cannot inspect runtime directory ownership"
(( runtime_owner == user_id )) || die "runtime directory is not owned by the current user"
checkpoint_key=$(printf '%s' "$source_dir/$checkpoint_name.vo" | sha256sum | awk '{ print $1 }') ||
  die "cannot derive checkpoint lock key"
checkpoint_lock=$runtime_dir/rocq-checkpoint-$checkpoint_key.lock
umask 077
exec 8>>"$checkpoint_lock" || die "cannot open checkpoint lock: $checkpoint_lock"
chmod 600 -- "$checkpoint_lock" || die "cannot protect checkpoint lock"
if ! flock -n 8; then
  printf 'checkpoint runner: another run is already producing %s.vo\n' "$checkpoint_name" >&2
  exit 75
fi

stage_dir=$(mktemp -d -- "$source_dir/.${checkpoint_name}.stage.XXXXXXXX") ||
  die "cannot create same-filesystem staging directory"
stage_live=1

cleanup() {
  local status=$?
  trap - EXIT
  if (( stage_live )); then
    rm -rf -- "$stage_dir"
  fi
  exit "$status"
}
trap cleanup EXIT

stage_dev=$(stat -c %d -- "$stage_dir") || die "cannot inspect staging filesystem"
destination_dev=$(stat -c %d -- "$source_dir") || die "cannot inspect destination filesystem"
[[ $stage_dev == "$destination_dev" ]] || die "staging and destination are not on the same filesystem"

stage_vo=$stage_dir/$checkpoint_name.vo
destination_vo=$source_dir/$checkpoint_name.vo

printf 'checkpoint runner: staging %s.vo in %s\n' "$checkpoint_name" "$stage_dir" >&2
if "$guard" env _ROCQ_CHECKPOINT_INTERNAL=1 "$script_dir/run-checkpoint-atomic.sh" \
  --internal-promote "$source_dir" "$source_name" "$stage_dir" "$destination_vo" -- "$@"; then
  command_status=0
else
  command_status=$?
fi

if (( command_status != 0 )); then
  printf 'checkpoint runner: guarded transaction failed with status %s; canonical %s was not changed\n' \
    "$command_status" "$destination_vo" >&2
  exit "$command_status"
fi
[[ -f $destination_vo && -s $destination_vo && ! -e $stage_vo ]] ||
  die "guarded transaction returned success without completing promotion"
rm -rf -- "$stage_dir"
stage_live=0
exit 0
