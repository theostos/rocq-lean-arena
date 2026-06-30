#!/usr/bin/env bash
set -euo pipefail

rocq_bin="${ROCQLKA_ROCQ:-rocq}"
rocq_cmd=("$rocq_bin")

if [[ -n "${ROCQLKA_OPAM_SWITCH:-}" ]]; then
  rocq_cmd=(opam exec --switch="${ROCQLKA_OPAM_SWITCH}" -- "$rocq_bin")
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat > "$tmpdir/RequireLean.v" <<'V'
From LeanImport Require Import Lean.
V

if ! "${rocq_cmd[@]}" compile -q "$tmpdir/RequireLean.v"; then
  cat >&2 <<'EOF'
rocq-lean-import is not available in the selected Rocq environment.

Install it with, for example:
  opam pin add --switch=rocq93_dev -n rocq-lean-import git+https://github.com/rocq-community/rocq-lean-import.git#master
  opam install --switch=rocq93_dev -y rocq-lean-import
EOF
  exit 1
fi

python3 - <<'PY'
import json
print("python-json-ok")
PY

echo "rocq-lean-import checker is available."
