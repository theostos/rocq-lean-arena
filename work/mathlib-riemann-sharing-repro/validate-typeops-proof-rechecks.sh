#!/usr/bin/env bash
# Read-only independent artifact checks, no importer plugin and no restart.
# The exclusive heavyweight guard requires serial scheduling with worker tests.
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
cd "$repo_dir"
python3 "$test_dir/check-target.py" work/mathlib-lie-trace-repro/proof-typeops-final \
  work/mathlib-lie-trace-repro/proof-prefix --manifest work/mathlib-lie-trace-repro/slice.json
python3 "$test_dir/check-target.py" "$test_dir/sset-typeops-final" "$test_dir/sset-prefix" \
  --manifest "$test_dir/sset-slice.json"
python3 "$test_dir/check-target.py" "$test_dir/derivative-typeops-final" "$test_dir/derivative-prefix" \
  --manifest "$test_dir/derivative-slice.json"
python3 "$test_dir/check-original-order.py" "$test_dir/riemannian-typeops-final"
printf 'Independent Mathlib artifact checks passed; production remains stopped.\n'
