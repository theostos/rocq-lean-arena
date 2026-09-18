#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
investigation_root=$PWD
investigation_unit="rocq-mathlib-timeout-investigation-$(date -u +%Y%m%dT%H%M%S)"
systemd-run --user --collect --unit="$investigation_unit" \
  --property="WorkingDirectory=$investigation_root" \
  --property=KillMode=control-group --property=RuntimeMaxSec=15600 \
  --property="StandardOutput=append:$investigation_root/work/mathlib-timeout-investigation/supervisor.log" \
  --property="StandardError=append:$investigation_root/work/mathlib-timeout-investigation/supervisor.log" \
  --setenv="ROCQ_MEMORY_OWNER_SERVICE=$investigation_unit.service" \
  /usr/bin/python3 "$investigation_root/work/mathlib-timeout-investigation/run.py"
