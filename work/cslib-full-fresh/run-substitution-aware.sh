#!/usr/bin/env bash
set -Eeuo pipefail
run_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$run_dir/../.." && pwd -P)
run_tag=${ROCQ_RUN_TAG:-substitution-aware}
[[ $run_tag =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Invalid ROCQ_RUN_TAG" >&2; exit 64; }
for log in "$run_dir/CslibFull.$run_tag.run.log" "$run_dir/CslibFull.$run_tag.guard.log"; do
  [[ ! -e $log ]] || { echo "Log already exists: $log; choose a new ROCQ_RUN_TAG." >&2; exit 64; }
done
cd -- "$repo_dir"
# Refuse a different experimental toolchain; never bypass library digests.
sha256sum --check --strict <<'EXPECTED'
93b97317727e726c7b27b45c829536fba090085832e508b99fff4d8b3aafe4d0  _worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe
80f5f5d5ee4d1e6b236931bfdd3757881661c1a2c54fd3dd00d0bea919d91a29  _worktrees/rocq-lean-import/compact-peano-importer-current/src/lean_import.cmxs
de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b  work/int32-tdiv-repro/foundation/Lean.vo
ce6fb77ab3905e0dbbc9668dad42f3cbfee474c131b472140cc4da94f8b323ae  _deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export
EXPECTED
# The singleton guard remains active throughout checking and atomic promotion.
exec > "$run_dir/CslibFull.$run_tag.guard.log" 2>&1
exec 'env' \
  '-u' \
  'LEAN_IMPORT_DECLARE_TRACE_LINE' \
  '-u' \
  'LEAN_IMPORT_TRANSLATION_TIMINGS' \
  '-u' \
  'LEAN_IMPORT_TRANSLATION_TRACE' \
  '-u' \
  'LEAN_IMPORT_TRANSLATION_BUCKETS' \
  '-u' \
  'LEAN_IMPORT_TRANSLATION_DEEP_TRACE' \
  '-u' \
  'LEAN_IMPORT_DISABLE_TRANSLATION_CACHE' \
  '-u' \
  'LEAN_IMPORT_VALIDATE_TRANSLATION_CACHE' \
  '-u' \
  'LEAN_IMPORT_DUMP_LEAN_AST' \
  '-u' \
  'LEAN_IMPORT_DUMP_ROCQ_AST' \
  '-u' \
  'LEAN_IMPORT_DUMP_CURRENT_DEF' \
  '-u' \
  'ROCQ_DIAGNOSTIC_CONVERSION_MEMO_LIMIT' \
  '-u' \
  'LEAN_IMPORT_DUMP_FAILED_DEF' \
  '-u' \
  'ROCQ_DIAGNOSTIC_PROJECTION_FIRST' \
  '-u' \
  'ROCQ_DIAGNOSTIC_CONVERSION_TRACE_PAIRS' \
  '-u' \
  'ROCQ_DIAGNOSTIC_CONVERSION_TRACE_FROM' \
  '-u' \
  'ROCQ_DIAGNOSTIC_MEMOIZE_CONVERSION_CALL' \
  '-u' \
  'ROCQ_DIAGNOSTIC_CONVERSION_CALL' \
  '-u' \
  'ROCQ_DIAGNOSTIC_NO_DIRECT_ARGUMENTS' \
  '-u' \
  'ROCQ_DIAGNOSTIC_NO_DEPENDENCY_FIRST' \
  '-u' \
  'ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL' \
  '-u' \
  'ROCQ_DIAGNOSTIC_DEPENDENCY_STATS' \
  '-u' \
  'ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES' \
  'LEAN_IMPORT_CHECKPOINT_STATS=1' \
  'ROCQ_DIAGNOSTIC_SERIALIZATION=1' \
  'ROCQ_MEMORY_POLL_SECONDS=0.25' \
  'OCAMLRUNPARAM=s=4M,o=5,i=5,a=2,v=21' \
  'ROCQ_MAX_RSS_KIB=3932160' \
  'ROCQ_MEMORY_MAX_KIB=4194304' \
  'ROCQ_MEMORY_HIGH_KIB=4194304' \
  'ROCQ_MIN_AVAILABLE_KIB=14155776' \
  'ROCQ_STACK_KIB=262144' \
  'ROCQ_MEMORY_SWAP_MAX_KIB=0' \
  "ROCQ_CHECKPOINT_LOG_FILE=${repo_dir}/work/cslib-full-fresh/CslibFull.${run_tag}.run.log" \
  "${repo_dir}/work/run-checkpoint-atomic.sh" \
  "${repo_dir}/work/cslib-full-fresh/CslibFull.v" \
  '--' \
  'timeout' \
  '--signal=TERM' \
  '--kill-after=5s' \
  '28800' \
  "${repo_dir}/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" \
  'c' \
  '-q' \
  '-bytecode-compiler' \
  'no' \
  '-R' \
  "${repo_dir}/_worktrees/rocq/stdlib-int32-repro/theories" \
  'Stdlib' \
  '-I' \
  "${repo_dir}/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
  '-Q' \
  "${repo_dir}/work/int32-tdiv-repro/foundation" \
  'LeanImport'
