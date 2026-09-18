#!/usr/bin/env bash
# Checker-only correction; no kernel worker or importer changes.
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
cd "$repo_dir"
while systemctl --user is-active --quiet rocq-typeops-proof-rechecks.service; do
  sleep 5
done
python3 -c 'import json,sys; sys.exit(json.load(open(sys.argv[1]))["exit_code"])' \
  "$test_dir/riemannian-typeops-final/independent-original-order.json"
python3 work/kernel-alignment-pass/gates.py final-gates-typeops-checked-serial
python3 work/kernel-alignment-pass/check-native.py final-gates-typeops-checked-serial
python3 work/kernel-alignment-pass/check-native.py final-gates-typeops-checked-serial strict-independent-check --strict --allow-uip
python3 work/kernel-alignment-pass/test-strict-checker.py strict-checker-typeops-checked
printf 'Checked-toolchain gates passed; production remains stopped.\n'
