#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
measurement_root=$PWD
measurement_unit="rocq-mathlib-cache-measurement-$(date -u +%Y%m%dT%H%M%S)"
systemd-run --user --collect --unit="$measurement_unit" \
  --property="WorkingDirectory=$measurement_root" \
  --property=KillMode=control-group --property=RuntimeMaxSec=7800 \
  --property="StandardOutput=append:$measurement_root/work/mathlib-cache-measurement/supervisor.log" \
  --property="StandardError=append:$measurement_root/work/mathlib-cache-measurement/supervisor.log" \
  --setenv="ROCQ_MEMORY_OWNER_SERVICE=$measurement_unit.service" \
  /usr/bin/python3 "$measurement_root/work/mathlib-cache-measurement/run.py"
