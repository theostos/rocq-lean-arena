#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tag=${1:?Usage: run-focused.sh UNIQUE_TAG}
for test in Fresh Prefix Target Reload Adjacent BooleanRegistration ComparisonControls; do
  bash "$repro_dir/run.sh" "$test" "$tag"
  printf 'PASS %s\n' "$test"
done
