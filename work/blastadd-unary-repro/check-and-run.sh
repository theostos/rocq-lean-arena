#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
run_tag=${1:?Usage: check-and-run.sh UNIQUE_TAG}
[[ $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
bash "$repro_dir/run.sh" DiscardedParameters "$run_tag-foundation"
python3 "$repro_dir/validate.py" \
  --foundation "$repro_dir/$run_tag-foundation/foundation/Lean.vo" \
  --directory "$repro_dir/$run_tag-regressions"
exec python3 "$repo_dir/scripts/run_cslib_from_start.py"
