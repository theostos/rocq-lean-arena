#!/usr/bin/env bash
# All checks use one immutable worker. No production restart is performed here.
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
cd "$repo_dir"
while [[ ! -f $test_dir/riemannian-typeops-cache-prepared/result.json ]]; do
  systemctl --user is-active --quiet rocq-typeops-candidate-validation.service || {
    printf 'Candidate validation stopped without a result.\n' >&2
    exit 1
  }
  sleep 5
done
/usr/bin/python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["exit_code"])' \
  "$test_dir/riemannian-typeops-cache-prepared/result.json"
python3 work/mathlib-lie-trace-repro/run.py work/mathlib-lie-trace-repro/ProofTarget.v \
  work/mathlib-lie-trace-repro/proof-typeops-final \
  --native --prefix work/mathlib-lie-trace-repro/proof-prefix --entries
python3 "$test_dir/run-traced.py" "$test_dir/SSetTarget.v" "$test_dir/sset-typeops-final" \
  --native --prefix "$test_dir/sset-prefix"
python3 "$test_dir/run-traced.py" "$test_dir/DerivativeTarget.v" "$test_dir/derivative-typeops-final" \
  --native --prefix "$test_dir/derivative-prefix"
python3 "$test_dir/run-traced.py" "$test_dir/RiemannianWholeFrom25M.v" \
  "$test_dir/riemannian-typeops-final" --checkpoint-limit 25000000
python3 work/kernel-alignment-pass/gates.py final-gates-typeops
python3 work/kernel-alignment-pass/check-native.py final-gates-typeops
python3 work/kernel-alignment-pass/check-native.py final-gates-typeops strict-independent-check --strict --allow-uip
python3 work/kernel-alignment-pass/test-strict-checker.py strict-checker-typeops
python3 "$test_dir/check-target.py" work/mathlib-lie-trace-repro/proof-typeops-final \
  work/mathlib-lie-trace-repro/proof-prefix --manifest work/mathlib-lie-trace-repro/slice.json
python3 "$test_dir/check-target.py" "$test_dir/sset-typeops-final" "$test_dir/sset-prefix" \
  --manifest "$test_dir/sset-slice.json"
python3 "$test_dir/check-target.py" "$test_dir/derivative-typeops-final" "$test_dir/derivative-prefix" \
  --manifest "$test_dir/derivative-slice.json"
python3 "$test_dir/check-original-order.py" "$test_dir/riemannian-typeops-final"
printf 'Final validation commands completed successfully; production remains stopped.\n'
