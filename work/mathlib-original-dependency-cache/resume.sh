#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
export ROCQ_APPROVED_WORKER_SHA256=ae3b7e159bd7eb582971ab86cf13abaf71dc435f2d5cc0cd3d8e184b0df44df5
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800 "$@"
