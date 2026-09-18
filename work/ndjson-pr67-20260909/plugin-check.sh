#!/usr/bin/env bash
set -Eeuo pipefail
task_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_dir="${1:-$task_dir/plugin-snapshot}/src"
review_prefix=/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/review/rocq-upstream-runtime-20260908/_build/install/default
export PATH="$review_prefix/bin:/home/theo/.opam/rocq93_native/bin:$PATH"
export OCAMLPATH="$review_prefix/lib:$task_dir/findlib"
export CAML_LD_LIBRARY_PATH="$review_prefix/lib/stublibs:/home/theo/.opam/rocq93_native/lib/stublibs"
scratch=$(mktemp -d "$task_dir/plugin-build-XXXXXXXX")
flags=(-thread -rectypes -bin-annot -strict-sequence -w +a-4-9-27-40..42-44-45-48-58-67-68-70 -warn-error +a-3 -package rocq-runtime.plugins.ltac,yojson -I "$scratch")
byte=(ocamlfind ocamlc "${flags[@]}")
native=(ocamlfind ocamlopt "${flags[@]}")
printf 'SOURCE\t%s\nBUILD\t%s\n' "$source_dir" "$scratch"
sha256sum "$source_dir/lean.ml" "$source_dir/leanExpr.mli" "$source_dir/leanParseNdjson.ml"
# The shim dispatches pp-mlg directly to Coqpp_main.main; no Rocq worker starts.
"$review_prefix/bin/rocq" pp-mlg "$source_dir/g_lean.mlg"
byte_objects=()
native_objects=()
for module in leanName leanExpr leanParseShared leanParse leanParseNdjson lean g_lean; do
  if [[ -f "$source_dir/$module.mli" ]]; then
    printf 'INTERFACE\t%s\n' "$module"
    "${byte[@]}" -c "$source_dir/$module.mli" -o "$scratch/$module.cmi"
  fi
  if [[ -f "$source_dir/$module.ml" ]]; then
    printf 'BYTECODE\t%s\n' "$module"
    "${byte[@]}" -c "$source_dir/$module.ml" -o "$scratch/$module.cmo"
    printf 'NATIVE\t%s\n' "$module"
    "${native[@]}" -for-pack Lean_import -c "$source_dir/$module.ml" -o "$scratch/$module.cmx"
    byte_objects+=("$scratch/$module.cmo")
    native_objects+=("$scratch/$module.cmx")
  fi
done
"${byte[@]}" -linkall -pack -o "$scratch/lean_import.cmo" "${byte_objects[@]}"
"${byte[@]}" -linkall -a -o "$scratch/lean_import.cma" "$scratch/lean_import.cmo"
"${native[@]}" -linkall -pack -o "$scratch/lean_import.cmx" "${native_objects[@]}"
"${native[@]}" -linkall -a -o "$scratch/lean_import.cmxa" "$scratch/lean_import.cmx"
"${native[@]}" -linkall -shared -o "$scratch/lean_import.cmxs" "$scratch/lean_import.cmxa"
printf 'PASS\tbytecode archive, native archive, and native plugin built\n'
ls -lh "$scratch/lean_import.cma" "$scratch/lean_import.cmxa" "$scratch/lean_import.cmxs"
