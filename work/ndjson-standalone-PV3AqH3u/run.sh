#!/usr/bin/env bash
set -Eeuo pipefail
task_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=/home/theo/Documents/github/rocq-lean-typechecker
stock=$repo_root/_worktrees/review/rocq-upstream-runtime-20260908
prefix=$stock/_build/install/default
stdlib=$repo_root/_worktrees/review/stdlib-upstream-20260908/theories
snapshot=$task_dir/source
export PATH="/home/theo/.opam/rocq93_native/bin:/usr/bin:/bin"
unset COQLIB ROCQLIB COQPATH ROCQPATH OCAMLPATH CAML_LD_LIBRARY_PATH
ulimit -s 65536
mkdir "$snapshot"
git -C "$repo_root/_deps/rocq-lean-import" archive 9a2326121fc1daedc90a60d990f8ebcca4ae899c | tar -x -C "$snapshot"
printf 'STAGE stock-runtime\n'
cd "$stock"
make -j1 dunestrap >"$task_dir/stock-dunestrap.log" 2>&1
timeout --signal=TERM --kill-after=5s 600 dune build -j2 rocq-runtime.install rocq-core.install >"$task_dir/stock-build.log" 2>&1
export PATH="$prefix/bin:$PATH"
export OCAMLPATH="$prefix/lib:$repo_root/work/ndjson-pr67-20260909/findlib"
export CAML_LD_LIBRARY_PATH="$prefix/lib/stublibs:/home/theo/.opam/rocq93_native/lib/stublibs"
export COQLIB="$prefix/lib/coq"
export ROCQLIB="$COQLIB"
export COQBIN="$prefix/bin/"
printf 'STAGE importer-build\n'
cd "$snapshot"
rocq --version
rocq makefile -f _CoqProject -R "$stdlib" Stdlib -o Makefile.rocq >"$task_dir/makefile.log" 2>&1
timeout --signal=TERM --kill-after=5s 180 make -j1 >"$task_dir/build.log" 2>&1
printf 'PASS importer-build\n'
cd tests
while IFS= read -r test_name; do
  [[ $test_name == *.v ]] || continue
  printf 'STAGE test %s\n' "$test_name"
  if timeout --signal=TERM --kill-after=5s 60 rocq c -q -bytecode-compiler no \
      -R "$stdlib" Stdlib -Q ../src LeanImport -I ../src -R . Test "$test_name" \
      >"$task_dir/${test_name%.v}.log" 2>&1; then
    printf 'PASS test %s\n' "$test_name"
  else
    printf 'FAIL test %s exit=%s\n' "$test_name" "$?"
  fi
done < _CoqProject
printf 'DONE\n'
