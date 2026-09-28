#!/usr/bin/env bash
# Reproduce the strict September 2026 Mathlib run from pinned sources.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
mkdir -p "${MATHLIB_REPRO_DIR:-$root/_build/mathlib-repro}"
repro=$(cd -- "${MATHLIB_REPRO_DIR:-$root/_build/mathlib-repro}" && pwd -P)
switch=${MATHLIB_OPAM_SWITCH:-rocq-mathlib-repro}
jobs=${JOBS:-4}
kernel=$repro/rocq
stdlib=$repro/stdlib
importer=$repro/rocq-lean-import
arena=$repro/lean-kernel-arena
prefix=$kernel/_build/install/default

checkout() {
  local url=$1 dir=$2 commit=$3
  if [[ ! -d $dir/.git ]]; then
    git init "$dir"
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch --depth=1 origin "$commit"
    GIT_LFS_SKIP_SMUDGE=1 git -C "$dir" checkout --detach FETCH_HEAD
  fi
  [[ $(git -C "$dir" rev-parse HEAD) == "$commit" ]] || {
    echo "Unexpected revision in $dir; use a fresh MATHLIB_REPRO_DIR." >&2
    exit 1
  }
}

runtime() {
  eval "$(opam env --switch="$switch" --set-switch)"
  export PATH="$prefix/bin:$PATH"
  export OCAMLPATH="$prefix/lib:$OPAM_SWITCH_PREFIX/lib"
  export COQBIN="$prefix/bin/"
  unset COQLIB COQCORELIB COQPATH ROCQLIB ROCQCORELIB ROCQPATH
  export ROCQRUNTIMELIB="$prefix/lib/rocq-runtime"
  ulimit -s 262144
}

case ${1:-} in
  build)
    if ! opam switch list --short | grep -Fxq "$switch"; then
      opam switch create "$switch" ocaml-base-compiler.4.14.2 --no-switch -y --jobs="$jobs"
    fi
    opam install --switch="$switch" -y --jobs="$jobs" \
      dune.3.23.1 ocamlfind.1.9.8 zarith.1.14 yojson.3.0.0
    checkout https://github.com/theostos/rocq.git "$kernel" \
      01d35a1f01e516f795ad6bdb8eed8ecffdc2b4e0
    checkout https://github.com/coq/stdlib.git "$stdlib" \
      3e47b26f345f36e375d81ade399eed0e310984b3
    checkout https://github.com/theostos/rocq-lean-import.git "$importer" \
      643ff336974d6b673b1b313481ba02548ff17694
    runtime
    (cd "$kernel"; make dunestrap; dune build --profile release -j "$jobs" \
      -p rocq-runtime,coq-core,rocq-core @install)
    # Build only the Stdlib modules required by Lean.v, and their dependencies.
    make -C "$stdlib/theories" Makefile.coq
    make -C "$stdlib/theories" -f Makefile.coq -j "$jobs" \
      ZArith/BinInt.vo NArith/BinNat.vo NArith/Nnat.vo ZArith/Znat.vo \
      micromega/Lia.vo micromega/ZifyBool.vo
    make -C "$importer" -j "$jobs" COQEXTRAFLAGS="-R \"$stdlib/theories\" Stdlib"
    rocq --version
    ;;
  export)
    checkout https://github.com/leanprover/lean-kernel-arena.git "$arena" \
      4ce4d513d6f38614d801ab95e4ac069fb3740b0d
    exporter=$arena/_build/lean4export/leanprover_lean4_v4.29.0
    checkout https://github.com/leanprover/lean4export.git "$exporter" \
      3de59f10bc4b4a0f2de698597aeb1246caa0df0a
    printf 'leanprover/lean4:v4.29.0\n' > "$exporter/lean-toolchain"
    export LEAN_NUM_THREADS="$jobs"
    (cd "$exporter"; lake build)
    (cd "$arena"; uv run --python 3.12 lka.py build-test mathlib)
    original=$arena/_build/tests/mathlib.ndjson
    printf 'a466d22a521f0fc0406b6d0ece2173f2b2e3d9eb4d8bc26a5e14316d39944d27  %s\n' \
      "$original" | sha256sum --check
    (cd "$arena/_build/tests/work/mathlib/src"; \
      lake env lean --run "$root/scripts/ProofWidgetsScope.lean" "$repro/ui-candidates.jsonl")
    # Match the successful run exactly: its first 40M records retained 40 UI declarations.
    python3 "$root/scripts/filter_proofwidgets.py" --source "$original" \
      --candidates "$repro/ui-candidates.jsonl" --output "$repro/mathlib.ndjson" \
      --preserve-through 40000000
    ;;
  check)
    runtime
    test -s "$repro/mathlib.ndjson"
    cat > "$repro/Check.v" <<'ROCQ'
From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Survey.
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 1800.
Lean Import "mathlib.ndjson".
ROCQ
    cd "$repro"
    export OCAMLRUNPARAM='s=4M,o=80,i=15,a=2,v=0,b'
    echo "Checking from record 1; progress: $repro/check.log"
    /usr/bin/time -v rocq repl -batch -q -bytecode-compiler no \
      -R "$stdlib/theories" Stdlib -Q "$importer/src" LeanImport -I "$importer/src" \
      -l Check.v > check.log 2>&1
    echo "PASS: strict import reached EOF. Log: $repro/check.log"
    ;;
  *) echo "Usage: $0 {build|export|check}" >&2; exit 2 ;;
esac
