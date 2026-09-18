#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat >&2 <<'EOF'
usage: run-memory-guarded.sh COMMAND [ARG ...]

Runs exactly one heavyweight command for the current user.  The command is
admitted only when MemAvailable can cover both the configured reserve and the
whole cgroup budget, and it is placed in a cgroup-v2 systemd scope with hard
memory and swap limits.

Environment (values in KiB unless noted):
  ROCQ_MAX_RSS_KIB             aggregate session RSS limit (default: 3145728)
  ROCQ_MEMORY_MAX_KIB          cgroup MemoryMax/budget (default: MAX_RSS)
  ROCQ_MEMORY_HIGH_KIB         cgroup MemoryHigh (default: MemoryMax)
  ROCQ_MEMORY_SWAP_MAX_KIB     cgroup MemorySwapMax (default: 0)
  ROCQ_MIN_AVAILABLE_KIB       system MemAvailable reserve (default: 15728640)
  ROCQ_STACK_KIB               hard per-process stack limit (default: 262144)
  ROCQ_ALLOW_EXTERNAL_ROCQ     allow an unguarded Rocq worker (0 or 1; default: 0)
  ROCQ_MEMORY_POLL_SECONDS     polling period, 0 < value <= 60 (default: 1)
  ROCQ_MEMORY_STATUS_SECONDS   status period, integer seconds (default: 15)
  ROCQ_MEMORY_TERM_GRACE_SECONDS  TERM grace, integer seconds (default: 2)
  ROCQ_MEMORY_OWNER_SERVICE    optional enclosing user service; stopping it also stops the scope
EOF
}

die() {
  printf 'memory guard: %s\n' "$*" >&2
  exit 78
}

is_positive_uint() {
  [[ $1 =~ ^[1-9][0-9]*$ && ${#1} -le 12 ]]
}

is_nonnegative_uint() {
  [[ $1 =~ ^(0|[1-9][0-9]*)$ && ${#1} -le 12 ]]
}

is_boolean() {
  [[ $1 == 0 || $1 == 1 ]]
}

validate_duration() {
  local name=$1 value=$2
  [[ $value =~ ^(0\.[0-9]+|[1-9][0-9]*(\.[0-9]+)?)$ ]] ||
    die "$name must be a positive number"
  LC_ALL=C awk -v value="$value" 'BEGIN { exit !(value > 0 && value <= 60) }' ||
    die "$name must be at most 60 seconds"
}

read_meminfo_kib() {
  local key=$1 value
  value=$(awk -v key="${key}:" '$1 == key { print $2; found = 1; exit } END { if (!found) exit 1 }' /proc/meminfo) ||
    die "cannot read $key from /proc/meminfo"
  is_positive_uint "$value" || die "invalid $key value: $value"
  printf '%s\n' "$value"
}

if (( $# == 0 )); then
  usage
  exit 2
fi

max_rss_kib=${ROCQ_MAX_RSS_KIB:-3145728}
memory_max_kib=${ROCQ_MEMORY_MAX_KIB:-$max_rss_kib}
min_available_kib=${ROCQ_MIN_AVAILABLE_KIB:-15728640}
memory_swap_max_kib=${ROCQ_MEMORY_SWAP_MAX_KIB:-0}
stack_kib=${ROCQ_STACK_KIB:-262144}
allow_external_rocq=${ROCQ_ALLOW_EXTERNAL_ROCQ:-0}
poll_seconds=${ROCQ_MEMORY_POLL_SECONDS:-1}
status_seconds=${ROCQ_MEMORY_STATUS_SECONDS:-15}
term_grace_seconds=${ROCQ_MEMORY_TERM_GRACE_SECONDS:-2}

is_positive_uint "$max_rss_kib" || die "ROCQ_MAX_RSS_KIB must be a positive base-10 integer"
is_positive_uint "$memory_max_kib" || die "ROCQ_MEMORY_MAX_KIB must be a positive base-10 integer"
is_positive_uint "$min_available_kib" || die "ROCQ_MIN_AVAILABLE_KIB must be a positive base-10 integer"
is_nonnegative_uint "$memory_swap_max_kib" || die "ROCQ_MEMORY_SWAP_MAX_KIB must be a nonnegative base-10 integer"
is_positive_uint "$stack_kib" || die "ROCQ_STACK_KIB must be a positive base-10 integer"
is_boolean "$allow_external_rocq" || die "ROCQ_ALLOW_EXTERNAL_ROCQ must be 0 or 1"
is_positive_uint "$status_seconds" || die "ROCQ_MEMORY_STATUS_SECONDS must be a positive base-10 integer"
is_positive_uint "$term_grace_seconds" || die "ROCQ_MEMORY_TERM_GRACE_SECONDS must be a positive base-10 integer"
(( status_seconds <= 3600 )) || die "ROCQ_MEMORY_STATUS_SECONDS must be at most 3600"
(( term_grace_seconds <= 60 )) || die "ROCQ_MEMORY_TERM_GRACE_SECONDS must be at most 60"
validate_duration ROCQ_MEMORY_POLL_SECONDS "$poll_seconds"

if [[ -v ROCQ_MEMORY_HIGH_KIB ]]; then
  memory_high_kib=$ROCQ_MEMORY_HIGH_KIB
  is_positive_uint "$memory_high_kib" || die "ROCQ_MEMORY_HIGH_KIB must be a positive base-10 integer"
else
  memory_high_kib=$memory_max_kib
fi

mem_total_kib=$(read_meminfo_kib MemTotal)
(( max_rss_kib <= mem_total_kib )) || die "ROCQ_MAX_RSS_KIB exceeds physical memory"
(( memory_max_kib <= mem_total_kib )) || die "ROCQ_MEMORY_MAX_KIB exceeds physical memory"
(( memory_high_kib <= memory_max_kib )) || die "ROCQ_MEMORY_HIGH_KIB must not exceed ROCQ_MEMORY_MAX_KIB"
(( memory_swap_max_kib <= mem_total_kib )) || die "ROCQ_MEMORY_SWAP_MAX_KIB exceeds physical memory"
(( min_available_kib <= mem_total_kib )) || die "ROCQ_MIN_AVAILABLE_KIB exceeds physical memory"
(( stack_kib <= memory_max_kib )) || die "ROCQ_STACK_KIB must not exceed ROCQ_MEMORY_MAX_KIB"
stack_bytes=$((stack_kib * 1024))
command -v prlimit >/dev/null 2>&1 || die "prlimit is unavailable; refusing to launch with an unchecked stack"

scope_base=rocq-lean-import-heavy
scope_unit=${scope_base}.scope
scope_marker=${_ROCQ_MEMORY_GUARD_SCOPED:-0}
cgroup_root=/sys/fs/cgroup

if [[ $scope_marker != 1 ]]; then
  [[ -r $cgroup_root/cgroup.controllers ]] || die "cgroup v2 is unavailable; refusing to launch"
  command -v systemd-run >/dev/null 2>&1 || die "systemd-run is unavailable; refusing to launch"
  systemctl --user show-environment >/dev/null 2>&1 ||
    die "the user systemd manager is unavailable; refusing to launch"
  if [[ $(systemctl --user show --property=LoadState --value "$scope_unit" 2>/dev/null || true) == loaded ]]; then
    printf 'memory guard: another heavyweight run already owns %s\n' "$scope_unit" >&2
    exit 75
  fi

  owner_args=()
  if [[ -n ${ROCQ_MEMORY_OWNER_SERVICE:-} ]]; then
    owner_service=$ROCQ_MEMORY_OWNER_SERVICE
    [[ $owner_service =~ ^[A-Za-z0-9_.@-]+\.service$ ]] ||
      die "invalid ROCQ_MEMORY_OWNER_SERVICE"
    enclosing_cgroup=$(awk -F: '$1 == "0" { print $3; found = 1; exit } END { if (!found) exit 1 }' /proc/self/cgroup) ||
      die "cannot inspect the enclosing service cgroup"
    [[ ${enclosing_cgroup##*/} == "$owner_service" ]] ||
      die "ROCQ_MEMORY_OWNER_SERVICE is not the enclosing service"
    # The scope is a sibling cgroup, so KillMode=control-group on the service
    # alone cannot stop it. Bind its lifetime to the verified enclosing unit.
    owner_args=("--property=BindsTo=$owner_service" "--property=After=$owner_service")
  fi

  script_path=$(readlink -f -- "${BASH_SOURCE[0]}") || die "cannot resolve this script"
  exec systemd-run \
    --user \
    --scope \
    --collect \
    --quiet \
    --unit="$scope_base" \
    --description="single guarded rocq-lean-import workload" \
    --property=MemoryAccounting=yes \
    --property="MemoryHigh=${memory_high_kib}K" \
    --property="MemoryMax=${memory_max_kib}K" \
    --property="MemorySwapMax=${memory_swap_max_kib}K" \
    "${owner_args[@]}" \
    env _ROCQ_MEMORY_GUARD_SCOPED=1 "$script_path" "$@"
fi

self_cgroup_rel=$(awk -F: '$1 == "0" { print $3; found = 1; exit } END { if (!found) exit 1 }' /proc/self/cgroup) ||
  die "cannot determine the managed cgroup"
[[ ${self_cgroup_rel##*/} == "$scope_unit" ]] ||
  die "scope marker is set outside $scope_unit; refusing to bypass confinement"
self_cgroup_dir=$cgroup_root$self_cgroup_rel
[[ -d $self_cgroup_dir ]] || die "managed cgroup directory is missing"

# systemd 255 does not expose MemoryOOMGroup= for transient scope units on
# this host.  Set the equivalent cgroup-v2 knob directly and fail closed if
# delegation does not let us make the whole scope an atomic OOM victim.
oom_group_file=$self_cgroup_dir/memory.oom.group
[[ -w $oom_group_file ]] || die "memory.oom.group is not writable; refusing to launch"
printf '1\n' >"$oom_group_file" || die "cannot enable cgroup-wide OOM killing"
[[ $(<"$oom_group_file") == 1 ]] || die "memory.oom.group did not remain enabled"

verify_cgroup_limit() {
  local file=$1 requested_kib=$2 value requested_bytes
  [[ -r $self_cgroup_dir/$file ]] || die "$file is unavailable in the managed cgroup"
  value=$(<"$self_cgroup_dir/$file")
  is_nonnegative_uint "$value" || die "$file is not a finite numeric limit"
  requested_bytes=$((requested_kib * 1024))
  (( value <= requested_bytes )) ||
    die "$file ($value bytes) is weaker than requested ($requested_bytes bytes)"
}

verify_cgroup_limit memory.high "$memory_high_kib"
verify_cgroup_limit memory.max "$memory_max_kib"
verify_cgroup_limit memory.swap.max "$memory_swap_max_kib"

user_id=$(id -u)
runtime_dir=${XDG_RUNTIME_DIR:-/run/user/$user_id}
[[ -d $runtime_dir && -w $runtime_dir ]] || die "runtime directory is unavailable: $runtime_dir"
runtime_owner=$(stat -c %u -- "$runtime_dir") || die "cannot inspect runtime directory ownership"
(( runtime_owner == user_id )) || die "runtime directory is not owned by the current user"
lock_file=$runtime_dir/rocq-lean-import-heavy.lock
umask 077
exec 9>>"$lock_file" || die "cannot open global lock: $lock_file"
chmod 600 -- "$lock_file" || die "cannot protect global lock metadata"
if ! flock -n 9; then
  holder=$(sed -n '1p' "$lock_file" 2>/dev/null || true)
  printf 'memory guard: another heavyweight run holds %s%s\n' \
    "$lock_file" "${holder:+ ($holder)}" >&2
  exit 75
fi
: >"$lock_file"
printf 'pid=%s started=%s command=' "$BASHPID" "$(date --iso-8601=seconds)" >&9
printf '%q ' "$@" >&9
printf '\n' >&9

# Every supported Rocq CLI replaces itself with one worker on Unix.  Refuse an
# unrelated worker before launch so a stale or manually started import cannot
# coexist with this supposedly single heavyweight workload.
pid_is_live() {
  local pid=$1 stat_line remainder state
  local -a stat_data=()
  # A process can exit between the readability check and the open. Bash's
  # $(<file) shortcut can then exit the supervisor despite an attached ||.
  # Read directly; NUL delimiting also preserves newlines in process names.
  mapfile -d '' -t stat_data 2>/dev/null </proc/"$pid"/stat || return 1
  stat_line=${stat_data[0]:-}
  [[ -n $stat_line ]] || return 1
  remainder=${stat_line##*) }
  state=${remainder%% *}
  [[ $state != Z && $state != X ]]
}

rocq_worker_pids() {
  ps -u "$user_id" -o pid=,comm= | awk '
    $2 ~ /^rocqworker/ || $2 ~ /^coqc(\.|$)/ { print $1 }
  '
}

inspect_rocq_workers() {
  local pid process_cgroup_rel
  scoped_rocq_workers=0
  external_rocq_workers=0
  while IFS= read -r pid; do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    process_cgroup_rel=$(
      awk -F: '$1 == "0" { print $3; found = 1; exit } END { if (!found) exit 1 }' "/proc/$pid/cgroup" 2>/dev/null
    ) || continue
    pid_is_live "$pid" || continue
    if [[ $process_cgroup_rel == "$self_cgroup_rel" ]]; then
      scoped_rocq_workers=$((scoped_rocq_workers + 1))
    else
      external_rocq_workers=$((external_rocq_workers + 1))
    fi
  done < <(rocq_worker_pids)
}

inspect_rocq_workers
if (( external_rocq_workers > 0 && allow_external_rocq == 0 )); then
  die "found $external_rocq_workers Rocq worker(s) outside the managed scope; refusing to launch"
fi

admission_budget_kib=$memory_max_kib
(( max_rss_kib > admission_budget_kib )) && admission_budget_kib=$max_rss_kib
required_available_kib=$((min_available_kib + admission_budget_kib))
available_kib=$(read_meminfo_kib MemAvailable)
if (( available_kib < required_available_kib )); then
  printf 'memory guard: refusing launch: MemAvailable=%s KiB; need at least reserve(%s) + budget(%s) = %s KiB\n' \
    "$available_kib" "$min_available_kib" "$admission_budget_kib" "$required_available_kib" >&2
  exit 75
fi
printf 'memory guard: admitted with MemAvailable=%s KiB, reserve=%s KiB, RSS limit=%s KiB, cgroup high/max/swap=%s/%s/%s KiB, stack=%s KiB\n' \
  "$available_kib" "$min_available_kib" "$max_rss_kib" \
  "$memory_high_kib" "$memory_max_kib" "$memory_swap_max_kib" "$stack_kib" >&2

guard_pid=$BASHPID
leader_pid=
session_id=
workload_started=0
workload_finished=0
launching=0
terminating=0

session_snapshot() {
  local snapshot
  snapshot=$(ps -eo pid=,sid=,stat=,rss= | \
    awk -v sid="$session_id" '$2 == sid && $3 !~ /^[ZX]/ { count++; rss += $4 } END { print count + 0, rss + 0 }') ||
    die "cannot inspect session memory"
  read -r session_member_count group_rss_kib <<<"$snapshot"
}

cgroup_current_kib() {
  local bytes
  bytes=$(<"$self_cgroup_dir/memory.current") || die "cannot read cgroup memory.current"
  is_nonnegative_uint "$bytes" || die "invalid cgroup memory.current value"
  printf '%s\n' "$(((bytes + 1023) / 1024))"
}

page_size_bytes=$(getconf PAGESIZE) || die "cannot determine the system page size"
is_positive_uint "$page_size_bytes" || die "invalid system page size: $page_size_bytes"
(( page_size_bytes % 1024 == 0 )) || die "system page size is not an integral number of KiB"
page_size_kib=$((page_size_bytes / 1024))

# Sum every live process in the managed cgroup, not just the original session.
# A command may legitimately create a nested session; excluding it here would
# make the soft RSS limit weaker than advertised (the cgroup hard limit would
# still apply, but only at the last possible moment).
scope_snapshot() {
  local pid total_pages resident_pages
  scope_member_count=0
  scope_rss_kib=0
  while IFS= read -r pid; do
    [[ $pid =~ ^[0-9]+$ && $pid != "$guard_pid" ]] || continue
    if read -r total_pages resident_pages _ <"/proc/$pid/statm" 2>/dev/null; then
      [[ $resident_pages =~ ^[0-9]+$ ]] || continue
      scope_member_count=$((scope_member_count + 1))
      scope_rss_kib=$((scope_rss_kib + resident_pages * page_size_kib))
    fi
  done <"$self_cgroup_dir/cgroup.procs"
}

emit_workload_pids() {
  local pid sid stat emitter_pid=$BASHPID
  if [[ -n $session_id ]]; then
    while read -r pid sid stat; do
      [[ $pid =~ ^[0-9]+$ && $sid == "$session_id" && $stat != Z* && $stat != X* ]] &&
        printf '%s\n' "$pid"
    done < <(ps -eo pid=,sid=,stat=)
  fi
  while IFS= read -r pid; do
    [[ $pid =~ ^[0-9]+$ && $pid != "$guard_pid" && $pid != "$emitter_pid" ]] || continue
    pid_is_live "$pid" && printf '%s\n' "$pid"
  done <"$self_cgroup_dir/cgroup.procs"
}

has_workload_pids() {
  local pid
  while IFS= read -r pid; do
    [[ -n $pid ]] && return 0
  done < <(emit_workload_pids)
  return 1
}

signal_workload() {
  local signal=$1 pid
  declare -A signalled=()
  while IFS= read -r pid; do
    [[ -n $pid && ! -v signalled[$pid] ]] || continue
    signalled[$pid]=1
    kill -s "$signal" -- "$pid" 2>/dev/null || true
  done < <(emit_workload_pids)
}

release_memory_high_for_shutdown() {
  local max_bytes current_high
  [[ -w $self_cgroup_dir/memory.high && -r $self_cgroup_dir/memory.max ]] || return 0
  max_bytes=$(<"$self_cgroup_dir/memory.max") || return 0
  current_high=$(<"$self_cgroup_dir/memory.high") || return 0
  if [[ $max_bytes =~ ^[0-9]+$ && $current_high =~ ^[0-9]+$ ]] &&
     (( current_high < max_bytes )); then
    printf '%s\n' "$max_bytes" >"$self_cgroup_dir/memory.high" || return 0
    printf 'memory guard: raised MemoryHigh to the unchanged hard limit for shutdown\n' >&2
  fi
}

terminate_workload() {
  local tick
  (( terminating == 0 )) || return 0
  terminating=1
  trap '' HUP INT TERM
  # A task throttled in mem_cgroup_handle_over_high may not process TERM/KILL
  # promptly.  Remove only the soft throttle before signalling; MemoryMax and
  # the no-swap limit remain unchanged throughout shutdown.
  release_memory_high_for_shutdown
  signal_workload TERM
  for ((tick = 0; tick < term_grace_seconds * 10; tick++)); do
    has_workload_pids || return 0
    sleep 0.1
  done
  signal_workload KILL
  for ((tick = 0; tick < 300; tick++)); do
    has_workload_pids || return 0
    sleep 0.1
  done
}

on_exit() {
  local status=$?
  trap - EXIT
  if (( (launching || workload_started) && !workload_finished && !terminating )); then
    printf 'memory guard: supervisor exiting unexpectedly; terminating the workload\n' >&2
    terminate_workload
  fi
  exit "$status"
}

on_signal() {
  local signal=$1 status=$2
  printf 'memory guard: received %s; terminating the complete workload\n' "$signal" >&2
  terminate_workload
  [[ -z $leader_pid ]] || wait "$leader_pid" 2>/dev/null || true
  workload_finished=1
  exit "$status"
}

trap on_exit EXIT
trap 'on_signal HUP 129' HUP
trap 'on_signal INT 130' INT
trap 'on_signal TERM 143' TERM

launching=1
prlimit --stack="$stack_bytes:$stack_bytes" -- setsid --wait "$@" &
leader_pid=$!
session_id=$leader_pid
workload_started=1
launching=0

# A non-interactive shell does not give this background child its own process
# group, so setsid keeps the PID and makes SID == PID.  Verify that invariant
# whenever the command lives long enough to observe it.
session_verified=0
for _ in {1..50}; do
  observed_sid=$(ps -o sid= -p "$leader_pid" 2>/dev/null | tr -d ' ' || true)
  [[ -n $observed_sid ]] || break
  if [[ $observed_sid == "$session_id" ]]; then
    session_verified=1
    break
  fi
  sleep 0.01
done
if pid_is_live "$leader_pid" && (( session_verified == 0 )); then
  printf 'memory guard: setsid did not establish the expected session; terminating\n' >&2
  terminate_workload
  wait "$leader_pid" 2>/dev/null || true
  workload_finished=1
  exit 78
fi

next_status_at=0
guard_failure=0
while :; do
  session_snapshot
  (( session_member_count > 0 )) || break
  scope_snapshot
  available_kib=$(read_meminfo_kib MemAvailable)
  current_cgroup_kib=$(cgroup_current_kib)
  inspect_rocq_workers

  if (( SECONDS >= next_status_at )); then
    printf 'memory guard: status %s: session=%s members(session/scope)=%s/%s Rocq workers=%s scope RSS=%s KiB; cgroup=%s/%s KiB; MemAvailable=%s KiB\n' \
      "$(date --iso-8601=seconds)" "$session_id" "$session_member_count" \
      "$scope_member_count" "$scoped_rocq_workers" "$scope_rss_kib" \
      "$current_cgroup_kib" "$memory_max_kib" "$available_kib" >&2
    next_status_at=$((SECONDS + status_seconds))
  fi

  if (( scoped_rocq_workers > 1 )); then
    printf 'memory guard: stopping workload because %s Rocq workers are active in the managed scope\n' \
      "$scoped_rocq_workers" >&2
    guard_failure=125
    break
  fi
  if (( external_rocq_workers > 0 && allow_external_rocq == 0 )); then
    printf 'memory guard: stopping workload because %s Rocq worker(s) appeared outside the managed scope\n' \
      "$external_rocq_workers" >&2
    guard_failure=125
    break
  fi

  if (( scope_rss_kib >= max_rss_kib )); then
    printf 'memory guard: stopping workload at aggregate scoped RSS %s KiB (limit %s KiB)\n' \
      "$scope_rss_kib" "$max_rss_kib" >&2
    guard_failure=125
    break
  fi
  if (( available_kib <= min_available_kib )); then
    printf 'memory guard: stopping workload with MemAvailable %s KiB (reserve %s KiB)\n' \
      "$available_kib" "$min_available_kib" >&2
    guard_failure=125
    break
  fi
  sleep "$poll_seconds"
done

if (( guard_failure != 0 )); then
  terminate_workload
  wait "$leader_pid" 2>/dev/null || true
  workload_finished=1
  exit "$guard_failure"
fi

# A descendant that called setsid is no longer in the original session, but it
# is still in the managed cgroup.  Never leave such a process behind.
if has_workload_pids; then
  printf 'memory guard: command leader/session ended with live scoped descendants; terminating them\n' >&2
  terminate_workload
  wait "$leader_pid" 2>/dev/null || true
  workload_finished=1
  exit 125
fi

if wait "$leader_pid"; then
  command_status=0
else
  command_status=$?
fi
workload_finished=1
if [[ -r $self_cgroup_dir/memory.peak ]]; then
  peak_bytes=$(<"$self_cgroup_dir/memory.peak")
  if [[ $peak_bytes =~ ^[0-9]+$ ]]; then
    printf 'memory guard: finished with status %s; cgroup peak=%s KiB (hard limit %s KiB)\n' \
      "$command_status" "$(((peak_bytes + 1023) / 1024))" "$memory_max_kib" >&2
  fi
fi
exit "$command_status"
