#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# Keep the previous entry point, now with a reusable 15M intermediate save.
exec bash "$repro_dir/../uint32-not-repro/resume-cslib.sh" "$@"
