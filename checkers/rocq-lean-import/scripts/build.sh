#!/usr/bin/env bash
set -euo pipefail

rocq_bin="${ROCQLKA_ROCQ:-rocq}"
rocq_cmd=("$rocq_bin")
env_cmd=()

if [[ -n "${ROCQLKA_OPAM_SWITCH:-}" ]]; then
  rocq_cmd=(opam exec --switch="${ROCQLKA_OPAM_SWITCH}" -- "$rocq_bin")
  env_cmd=(opam exec --switch="${ROCQLKA_OPAM_SWITCH}" --)
fi

importer_root="${ROCQLKA_IMPORTER_ROOT:-}"
rocq_compile_args=()
if [[ -n "$importer_root" ]]; then
  if [[ ! -d "$importer_root/src" ]]; then
    echo "Importer source directory not found: $importer_root/src" >&2
    exit 1
  fi
  importer_root="$(cd "$importer_root" && pwd -P)"
  jobs="${ROCQLKA_BUILD_JOBS:-2}"
  "${env_cmd[@]}" make -C "$importer_root" -j"$jobs"
  rocq_compile_args=(-I "$importer_root/src" -Q "$importer_root/src" LeanImport)
fi

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat > "$tmpdir/RequireLean.v" <<'V'
From LeanImport Require Import Lean.
V

if ! "${rocq_cmd[@]}" compile "${rocq_compile_args[@]}" -q "$tmpdir/RequireLean.v"; then
  if [[ -n "$importer_root" ]]; then
    echo "The selected rocq-lean-import worktree did not load: $importer_root" >&2
    exit 1
  fi
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
