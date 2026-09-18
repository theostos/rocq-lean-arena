#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
export ROCQ_APPROVED_WORKER_SHA256=2d631c655cb65e6b1998886414c36ef10e5a322826b613e338a15009cc090c9f
exec python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800 "$@"
