# Persistent reduction experiment — 2026-09-14

Historical experiment, superseded by `TWO-VIEW-EXPERIMENT.md`. The first memo
and selective no-update implementations described here were REJECTED. Neither
is present in the current CClosure source. Production remains stopped.

Status: **unvalidated**. User authorized continuing the structural repair after
the Lean source review. Production is stopped; do not run the draft resume.py.

The weighted portfolio was rejected (Lie target timeout120). Its source is
preserved as kernel Git blob `e52326ba8d94edd73d0c225e2cf14bc3ea6ac26f` and
`conversion.weighted.ml`. The pre-experiment CClosure is preserved as blob
`f485185999e74298661f06451071b31a415478fb` (all earlier user/kernel changes intact).
These are object backups, not commits. Do not reset either worktree to HEAD.

Current conversion.ml exactly matches the earlier pre-portfolio source
`fe6c874a2f7f60507aa06515627e6cee726bb3ae`, SHA
`54b305d29a16ee2718074561bd53ae74dea3ea663acd509802736c03b12ee2c4`:
cheap256 shared attempt, then the non-sharing constructor/dependency strategy,
then ordinary fallbacks. The rejected portfolio helpers are removed, as is their
invocation in the main witness test. Historical test files remain as evidence.

CClosure now has an experimental bounded WHNF memo for non-sharing conversion
when the importer heuristic flag is enabled. It stores completed reductions
separately rather than updating original cells. Entries are local to each
reduction table (separate left/right heaps), keyed by the input closure identity,
a bounded flat application/projection/shift stack, exact reduction settings,
infos-cache identity (environment/universes/evars/mode) and relevance context.
No update/recursor/primitive frames or optional inspection queries are cached.
4096 entries per table, at most8 variants per head. A global mutation serial
with rollover epoch conservatively invalidates retained views after any closure
contents rewrite. Mutating or throwing computations install no entry.

No public .mli, importer, serialized state, registration, or checking flag changes.
This avoids the actual CClosure interface dependency recorded in the pinned
plugin. The replay successfully loads that unchanged plugin and existing proof
prefixes. Private closure tests plus new `whnf_memo_test.ml` pass (symbolic input
preserved, reuse, settings/context separation, mutation/epoch invalidation,
inspection/shared/oversized exclusions, exception handling, bounded eviction).

Candidate worker: `e963faf6d76675756a84e6befc84847a66afc195e68c8452ae9e054ddf47704e`.
CClosure source: `2b0552e3367ad531e8025eab11230d1a014a5027e203e961c66d08877fffc7c2`.

`sset-persistent-memo`: timeout at unchanged120s (125.21s total). Stalls in
conversion call221 (constructor_relevance=true, dependency=true) comparing
autoParam applications. Therefore this memo by itself does NOT solve the
unfolding-order problem. In the weighted experiment the ordinary strategy
solved that comparison quickly. `sset-plain-persistent` is now testing ordinary
conversion with `Unset Kernel Term Sharing`, via the explicitly recorded
NO_DEPENDENCY_FIRST diagnostic. If it passes, test `LieNoSharing.v` using the same
wrapper and the Lie `proof-prefix`, then `DerivativeNoSharing.v` with its own
prefix. These controls are diagnostics, not production validation.

The final decision must be based on real opposing-case replays, not mock cache
tests. Rebuilds/replays stay sequential under the memory guard. Do not promote
this worker or say all Mathlib is verified.
