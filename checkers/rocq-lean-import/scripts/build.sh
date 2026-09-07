#!/usr/bin/env bash
set -euo pipefail

if [[ ${ROCQLKA_BUILD_JOBS:-1} != 1 ]]; then
  echo "ROCQLKA_BUILD_JOBS must be 1: concurrent Rocq workers are disabled." >&2
  exit 3
fi

# Cover both make and the importer-load smoke test with the same guard.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/run-memory-guarded.sh" "$script_dir/build-internal.sh" "$@"
