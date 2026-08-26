#!/usr/bin/env bash
set -euo pipefail

switch_name="${ROCQLKA_OPAM_SWITCH:-rocq93_clean}"
rocq_commit="f756383de2e66f63c95815c73838596d7d97c1c2"
stdlib_commit="3e47b26f345f36e375d81ade399eed0e310984b3"

if ! opam switch list --short | grep -Fxq "$switch_name"; then
  opam switch create "$switch_name" ocaml-base-compiler.4.14.2 -y
fi

opam pin add --switch="$switch_name" -n rocq-runtime \
  "git+https://github.com/rocq-prover/rocq.git#$rocq_commit"
opam pin add --switch="$switch_name" -n rocq-core \
  "git+https://github.com/rocq-prover/rocq.git#$rocq_commit"
opam pin add --switch="$switch_name" -n rocq-stdlib \
  "git+https://github.com/coq/stdlib.git#$stdlib_commit"
opam install --switch="$switch_name" -y rocq-core rocq-stdlib

opam exec --switch="$switch_name" -- rocq --version
