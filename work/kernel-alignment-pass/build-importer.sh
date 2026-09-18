#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
original=${ROCQ_ALIGNMENT_IMPORTER_SOURCE:-$repo_dir/_worktrees/rocq-lean-import/cslib-ndjson}
test -f "$original/src/lean.ml"
importer=$(mktemp -d -- "$test_dir/importer.XXXXXXXX")
printf 'Staged importer: %s\n' "$importer"
rsync -a --exclude='.git' --exclude='_build' --exclude='*.cm*' \
  --exclude='*.o' --exclude='*.a' --exclude='*.vo*' --exclude='*.glob' \
  --exclude='Makefile.rocq*' --exclude='.*.aux' --exclude='.*.d' \
  "$original/" "$importer/"
prefix=$repo_dir/_worktrees/rocq/compact-peano-view/_build/install/default
yojson=/home/theo/.opam/coq820_dev/lib/yojson
test -f "$yojson/META"
mkdir -p "$importer/_build/findlib"
ln -s "$yojson" "$importer/_build/findlib/yojson"
export PATH="$prefix/bin:/home/theo/.opam/rocq93_native/bin:$PATH"
export OCAMLPATH="$prefix/lib:$importer/_build/findlib"
timeout 90s prlimit --as=2147483648 --cpu=75 -- \
  make -C "$importer" -j1 src/lean_import.cmxs
