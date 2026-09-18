#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
cd -- "$test_dir"
/home/theo/.opam/rocq93_native/bin/ocamlfind ocamlopt \
  -rectypes -thread -package rocq-runtime.vernac -linkpkg \
  inspect_vo_summary.ml -o inspect_vo_summary.exe
./inspect_vo_summary.exe \
  "$repo_dir/_worktrees/rocq-lean-import/compact-peano-importer-current/src/Lean.vo" \
  "$repo_dir/_worktrees/rocq/compact-peano-view/_build/default/theories/Corelib/Init/Prelude.vo" \
  "$repo_dir/_worktrees/rocq/kernel-physical-hconstr/_build/default/theories/Corelib/Init/Prelude.vo" \
  "$repo_dir/_worktrees/rocq/eager-diagnostic-gates/_build/default/theories/Corelib/Init/Prelude.vo" \
  /home/theo/.opam/rocq93_native/lib/rocq-core/rocq.d/Init/Prelude.vo
