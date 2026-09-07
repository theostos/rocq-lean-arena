#!/usr/bin/env bash
set -euo pipefail

# Keep conversion, compilation, and their descendants in one bounded scope.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec "$script_dir/run-memory-guarded.sh" "$script_dir/run-internal.sh" "$@"
