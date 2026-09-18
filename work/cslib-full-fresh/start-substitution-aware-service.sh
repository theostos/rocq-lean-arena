#!/usr/bin/env bash
set -Eeuo pipefail

if (( $# != 1 )) || [[ ! $1 =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "Usage: bash start-substitution-aware-service.sh UNIQUE_RUN_TAG" >&2
  exit 64
fi
run_tag=$1
run_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$run_dir/../.." && pwd -P)
unit=rocq-cslib-$run_tag.service
for kind in service run guard; do
  [[ ! -e $run_dir/CslibFull.$run_tag.$kind.log ]] || {
    echo "Logs already exist for $run_tag; choose a new tag." >&2
    exit 64
  }
done

# A transient user service survives terminal disconnection, not logout/reboot.
# The guard binds its separate scope to this verified enclosing service.
exec systemd-run --user --unit="$unit" --service-type=exec \
  --property=TimeoutStopSec=45 --property=KillMode=control-group \
  --property="StandardOutput=append:$run_dir/CslibFull.$run_tag.service.log" \
  --property=StandardError=inherit --working-directory="$repo_dir" \
  /usr/bin/env "ROCQ_RUN_TAG=$run_tag" "ROCQ_MEMORY_OWNER_SERVICE=$unit" \
  /usr/bin/bash "$run_dir/run-substitution-aware.sh"
