#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
tag=${1:?Usage: run-focused.sh UNIQUE_TAG}
for test_name in Fresh Prefix Target Adjacent SubstitutionDependency Reload; do
  bash "$repro_dir/run.sh" "$test_name" "$tag"
  printf 'Passed %s\n' "$test_name"
done
