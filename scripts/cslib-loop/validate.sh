#!/usr/bin/env bash
# Fixed, sequential gates. The supervisor runs these without a model turn.
set -Eeuo pipefail
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
tag=${1:?Unique validation tag required}
[[ $tag =~ ^[A-Za-z0-9_.-]+$ ]] || exit 64
cd -- "$repo_dir"
bash work/unit-projection-repro/check-toolchain.sh
bash work/uint32-shift-repro/run-regressions.sh "$tag"
python3 -m unittest discover -s scripts/tests -p test_sealed_checkpoint.py
python3 -m unittest discover -s scripts/tests -p test_chunked_import.py
bash work/lrat-restore-repro/check-prefix15m-load.sh "$tag"
