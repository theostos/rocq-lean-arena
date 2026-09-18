#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
importer=$root/_worktrees/rocq-lean-import/cslib-ndjson
prefix=$root/_worktrees/rocq/compact-peano-view/_build/install/default
yojson=${NDJSON_YOJSON_DIR:-/home/theo/.opam/coq820_dev/lib/yojson}
test -f "$yojson/META"
mkdir -p "$importer/_build/findlib"
if [[ ! -e "$importer/_build/findlib/yojson" ]]; then
  ln -s "$yojson" "$importer/_build/findlib/yojson"
fi
export PATH="$prefix/bin:/home/theo/.opam/rocq93_native/bin:$PATH"
export OCAMLPATH="$prefix/lib:$importer/_build/findlib"
timeout 90s prlimit --as=2147483648 --cpu=75 -- make -C "$importer" -j1 src/lean_import.cmxs
