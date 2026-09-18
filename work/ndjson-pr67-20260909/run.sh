#!/usr/bin/env bash
set -Eeuo pipefail
task_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_dir=$(cd -- "${1:-$task_dir/baseline}/src" && pwd -P)
review_prefix=/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/review/rocq-upstream-runtime-20260908/_build/install/default
export PATH="$review_prefix/bin:/home/theo/.opam/rocq93_native/bin:$PATH"
export OCAMLPATH="$review_prefix/lib:$task_dir/findlib"
export CAML_LD_LIBRARY_PATH="$review_prefix/lib/stublibs:/home/theo/.opam/rocq93_native/lib/stublibs"
scratch=$(mktemp -d "$task_dir/build-XXXXXXXX")
compiler=(ocamlfind ocamlc -rectypes -thread -package rocq-runtime.vernac,yojson -I "$scratch")
objects=()
for module in leanName leanExpr leanParseShared leanParse leanParseNdjson; do
  "${compiler[@]}" -c "$source_dir/$module.mli" -o "$scratch/$module.cmi"
  if [[ -f $source_dir/$module.ml ]]; then
    "${compiler[@]}" -c "$source_dir/$module.ml" -o "$scratch/$module.cmo"
    objects+=("$scratch/$module.cmo")
  fi
done
"${compiler[@]}" -c "$task_dir/support.ml" -o "$scratch/support.cmo"
objects+=("$scratch/support.cmo")
status=0
test_modules=(structural)
if rg -q 'kernel_opaque' "$source_dir/leanExpr.mli"; then
  test_modules+=(ndjson_hint_tests)
else
  test_modules+=(baseline_hints)
fi
if rg -q 'skip_declarations' "$source_dir/leanParseNdjson.mli"; then
  test_modules+=(ndjson_prefix_tests)
fi
printf 'SOURCE\t%s\nBUILD\t%s\n' "$source_dir" "$scratch"
for test_name in "${test_modules[@]}"; do
  "${compiler[@]}" -c "$task_dir/$test_name.ml" -o "$scratch/$test_name.cmo"
  "${compiler[@]}" -linkpkg "${objects[@]}" "$scratch/$test_name.cmo" -o "$scratch/$test_name.exe"
  timeout --signal=TERM --kill-after=2s 30 "$scratch/$test_name.exe" "$task_dir/baseline/dumps" || status=1
done
exit "$status"
