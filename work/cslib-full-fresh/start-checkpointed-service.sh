#!/usr/bin/env bash
set -Eeuo pipefail
(( $# == 1 || $# == 2 )) && [[ $1 =~ ^[A-Za-z0-9_-]+$ && ${2:---resume} == --resume ]] || {
  echo 'Usage: start-checkpointed-service.sh RUN_TAG [--resume]' >&2
  exit 64
}
run_tag=$1
run_base=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$run_base/../.." && pwd -P)
stamp=$(date +%Y%m%dT%H%M%S%N)
unit=rocq-cslib-$run_tag-$stamp.service
mkdir -p -- "$run_base/runs"
service_log=$run_base/runs/$run_tag.$stamp.service.log
args=("$repo_dir/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export"
  ce6fb77ab3905e0dbbc9668dad42f3cbfee474c131b472140cc4da94f8b323ae
  11005951 "$run_tag")
[[ $# == 1 ]] || args+=(--resume)
systemd-run --user --unit="$unit" --service-type=exec \
  --property=TimeoutStopSec=45 --property=KillMode=control-group \
  --property="StandardOutput=append:$service_log" --property=StandardError=inherit \
  --working-directory="$repo_dir" \
  /usr/bin/env "ROCQ_MEMORY_OWNER_SERVICE=$unit" \
  ROCQ_MAX_RSS_KIB=15728640 ROCQ_MEMORY_MAX_KIB=16777216 ROCQ_MIN_AVAILABLE_KIB=6291456 \
  /usr/bin/bash "$run_base/run-checkpointed.sh" "${args[@]}"
printf 'Service: %s\nService log: %s\n' "$unit" "$service_log"
printf 'Watch: tail -n 5 -F %s/runs/%s/latest/*.log\n' "$run_base" "$run_tag"
