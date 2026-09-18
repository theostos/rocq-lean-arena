# Lie trace timeout (28,200,411)

## RESUMED, 2026-09-14 11:25 Europe/Paris

resume.py exited0. Service rocq-mathlib-alignment-5m-lie-sharing.service is
active/running, MainPID929199, invocation fe9e55265f9e40ba965ee2334b08eb9a.
It resumes the sealed generation at line25,000,001. See resume-approval.json
for pinned evidence and launch command. No assistant monitoring after startup.
Full Mathlib is NOT yet verified to EOF; do not infer that from this repair.

## VALIDATION COMPLETE, 2026-09-14 11:25 Europe/Paris

Candidate worker ce98e4acc636eb5506b2294f6a6edb16bbf65b8503be2a0f09d8b8041cee28fb
passed `final-gates-lie-sharing-retry` (15 native,20 legacy,44 importer,
204 runner tests passed/2 opt-in skips). Both independent native modes passed
with dependencies rechecked; all11 strict-checker-lie-sharing profile controls
passed. The clean proof-final replay passed in55.991s (import done CPU19.619s),
ProofTarget.vo 8a0e3ecee1bac78ccd177bcf86e20be0ec3c5bf342d1cebfcbcdf111332bbd22.
proof-final/independent-target.json also passed (target-only scope, dependencies
reused from the previously typechecked all-proof prefix).

resume.py is now checking pinned records before starting the service from25M.
Confirm its exit0 and service startup before claiming the loop is resumed.
Do not monitor full Mathlib afterward. The 25M chain has not been deleted or
rewritten. `FIX.md` is the concise report; everything below is historical.

## Candidate passed, 2026-09-14 11:10 Europe/Paris

`proof-local-sharing-retry`: EXIT0, wall58.794s including prefix loading and
checkpoint serialization. Import finished before CPU20.370s. Normal global
sharing is enabled; no conversion-policy diagnostic controls were used.
Worker: ce98e4acc636eb5506b2294f6a6edb16bbf65b8503be2a0f09d8b8041cee28fb.
Checker: 4fdc763343aadf5673433783f536a45502ddd2e36ca35392f9e38c4bad4d1c0b.
ProofTarget.vo: 8175ba3179ec0aed4a369207e92231c579a84107f9a4bb1aaad23582b827e461.

Private runtime suites and all 15 native +20 legacy regressions passed. Broad
gate `final-gates-lie-sharing-retry` is still running importer regressions.
Do not edit its pinned kernel/private-test inputs before completion.
Next: clean replay in proof-final; independent native checks (including strict
mode, explicit UIP bridge), strict checker rejection controls, supplementary
target-only checker run via check-target.py. That last check reuses dependencies
and must not be described as independent validation of the entire proof prefix.
Only after these pass, resume.py starts the background loop from25M and ends
assistant monitoring after the startup check. No run has been resumed yet.

## Latest status, 2026-09-14 11:07 Europe/Paris

BREAKTHROUGH: disabling destructive reduction sharing solves the proof-retaining
target. `proof-no-sharing` passes (full trial worker, target done at CPU19.285s).
After removing all trial optimizations, `proof-no-sharing-baseline` also passes:
exit0, wall59.514s including serialized checkpoint, target done before CPU21.634s.
Worker c42fffa304564fd25d6f04aca508d8b9bd2a8dfa2d7003cd459e25e9423b749a.
All dependency proofs remain in `proof-prefix`, no axiomatized slice used.

The speculative caches/source-alignment/DAG/scheduling changes have been removed.
Successful full trial source is recoverable as Git blob
409bad1401e252ceb6f7ac50f17eff422bfcdda5 in the kernel worktree (not a commit).
The reconstructed pre-trial source hash is
1b58bd61d68b58be08b71e7597f881ea0456a9b31c6c14e94cd5e5e9827cd44b;
it does not byte-match the original baseline, so do not claim exact restoration.

Current candidate is a small local non-destructive retry in `gen_conv`:
keep the initial bounded shared attempt; use a derived environment with only
share_reduction=false for the subsequent constructor/dependency guided attempt.
Global settings, untyped conversion, checking flags and APIs remain unchanged.
`proof-local-sharing-retry` is running on ProofTarget.v WITHOUT Unset Sharing.
Private regression coverage added as conversion_retry_test.ml to the witness
suite. Full gates and independent checking still pending. No full run resumed.

The notes below describe older trials and are superseded by this section.

## Current status, 2026-09-14 10:34 Europe/Paris

**No fix is validated; no full loop has been resumed.** The 25M checkpoint
chain is untouched. All trial changes currently affect `conversion.ml` only;
the original heavily modified kernel files must not be reset to git HEAD.

The all-proof `proof-prefix/ProofPrefix.vo` completed successfully in 1299.50s,
SHA256 `58e7b89ab0fe3b8c10b26a0b494ae4af9bdc264991968e1165131610fb426c0e`.
It retains every dependency proof and allows target-only replays in ~11s plus
the target's execution time. The target timeout in ProofTarget.v is 120s.

Completed all-proof target experiments (all reached the 120s timeout):
baseline, fast-stack hint, bounded whole-record projection-source congruence,
nested whole-record congruence, isolated lazy projection-source alignment,
Lean-style scalar simultaneous delta, late eta, bounded syntactic DAG memo,
right-to-left arguments without constructor-first ordering, flat total-work
congruence budget, hierarchical total-work congruence budgets, source trimming,
and explicit projection-head reduction within source alignment. Artifact
directories are `proof-target-*`. Most reach a slow product at call922/923;
the hierarchical work-budget variant stalls earlier at a Module comparison.
Both total-work-budget changes were removed. The scalar-delta and late-eta
diagnostic branches remain inactive and must be removed before promotion.

The proof-trace-probe-cost experiment shows indirect dependency inspection is
only a small fraction of runtime (32768 calls consume 1.719s cumulative CPU).
The success memo is not full. No cache capacity increase is justified.

At product call922, trace step50 compares two semiring inheritance paths:
`Ring.toSemiring (DivisionRing.toRing (Field.toDivisionRing K
  (AlgebraicClosure.instField k F)))` versus
`CommSemiring.toSemiring (CommRing.toCommSemiring K
  (AlgebraicClosure.instCommRing k F))`.
The bounded complete term dump is in proof-trace-module-instance/run.log.
The focused native `FieldPath.v` fixture checks those paths quickly against
the prefix (`field-path-baseline-2`, exit0, 5.71s including prefix loading).

The current trial has bounded syntactic DAG memoization, syntactic stack
comparison, and an isolated bounded projection-source alignment helper.
The helper now handles FProj heads (not just FFlex). If snapshot copying fails,
it optionally quotes only sources whose combined expanded syntax fits1024
nodes, avoiding unrelated captured substitution entries. Rebuilding MUST use
`subs_id (Range.length (info_relevances infos))`, not inject/subs_id0, to preserve
local binder meaning. The focused test caught this and now passes.

Current replay `proof-target-whnf-fast` additionally tries the existing bounded
syntactic head/stack equality immediately after each WHNF step. This is still
an experiment, not validation. `test-fast-stack.sh` passes including separately
allocated shared DAGs, relocation/shape negatives, bounded divergent input,
projection-head beta reduction, and no mutation of input closures.

The diagnostic PROCESS_STEP dump in eqwhnf and its wrapper whitelist entry
also need removal before any production promotion. Other work files include
Inspect.v, InspectPaths.v and their definition-printing results.

Older notes below describe historical states, not the active kernel.

### 10:50 update: small-expression cache and pending weakening normalization

The source trial now additionally has a second per-conversion success cache:
bounded quotation (512 combined expanded nodes), Constr.hcons canonical raw
syntax, explicit external lifts applied, positive completed conversions only,
2048 total entries and8 context variants per term pair. Contexts currently
remain exact physical relevance/type/type-lift ranges. No API/interface change.
Private witness tests and small_cache_test.ml pass. The latter tests rebuilt
closures, relocation, context/problem separation, eviction and refusal to
quote a 2^50-node expanded closure DAG. test-fast-stack.sh runs both tests.

The128-node experiment still times out120s but a60s profile showed10954 raw
cache hits out of29118 eligible keys and over524288 WHNF/eqappr trace steps.
That is substantial reuse, but not a passing theorem. The512-node candidate
is currently in `proof-long-small-cache-512` with a600s line timeout. It stalls
at product call916 (the trace selector917 therefore misses that call).
No validation/promotion/restart. Session57710 owns that wrapper.

The exact current conversion.ml trial is preserved as a local git blob in the
kernel repository: `26146c7d12a80fce2dbda66ddf4fd33e7a54ff20` (git hash-object).
This includes all unpromoted trial changes. The original baseline SHA256 is
still94dac57b... below; never reset the whole dirty kernel to git HEAD.

An attempted perf profile was denied by perf_event_paranoid=4; do not change
system permissions. An earlier small-expression-cache run accidentally used
the preceding worker after a compile error and was deliberately interrupted
via SIGINT; it is NOT a candidate benchmark. The corrected run has suffix-2.

Next hypothesis, NOT IMPLEMENTED: make bounded raw keys weakening-aware.
Current cache cannot reuse comparisons beneath unused extra lambda binders:
both de Bruijn indices and exact context ranges differ, unlike Lean's stable
free-variable identities. After bounded quotation, find the minimum free Rel
across both terms (binder-aware traversal). Drop at most min_free_rel-1 newest
local binders, capped by the equal lengths of all three context ranges. Lower
both terms with Vars.lift(-drop), and use Range.skipn(drop) on relevances,
rel_types and rel_type_lifts in the cache key. Never remove a referenced local;
external Environ stays fixed for the whole conversion. First implement/test
the simpler case of dropping ALL local binders only if Vars.noccur_between
1 depth holds on both terms, if preferred. Test referenced-local negatives,
weakening under internal binders, distinct retained contexts and no escape of
the per-conversion scope. Do not accept an in-progress pair as equality.

The full NDJSON generation failed after 1,800 seconds on
`LieModule.lowerCentralSeries_one_inf_center_le_ker_traceForm`.
The intact last checkpoint is 25,000,000; the background service is inactive.
Nothing has been restarted/promoted. No checkpoints have been deleted.

## Baseline restored, 2026-09-14 09:11 Europe/Paris

The trial changes to `kernel/conversion.ml` and
`work/kernel-alignment-pass/test-witness-candidate.sh` have been reversed.
Their SHA256 hashes exactly match `final-gates-except-conds-2/passed.json`:

* conversion: `94dac57b228a15c15c0849de16403492d2cc8f13f13e607b4fda085064ba8f52`
* test script: `3bb36e140c5093db0c5fb9302745dd21d30bdd69ebdfa4c8ea8e7df452201b53`

The restored worker is expected to match `11acf908...` (check artifact hash).
An all-proof `ProofPrefix.v` replay is running in `proof-prefix`, followed by
`ProofTarget.v` from its saved prefix. The prefix has **no abstracted proofs**.
Its dependency export is `LieTrace.stream.lean-export` (2,866,592 lines), with
the target on its final line. All source hashes are in `slice.json`.

## Diagnostic experiments — NOT verification

`DiagnosticPrefix.vo` has 1,689 abstracted dependency proofs. It permits fast
target-only experiments, but is not admissible as full-proof validation.
`Diagnostic.stream.lean-export` ends at line 247,148. The target takes about
one second to load from this prefix; its initial dependency compile was 107s.

* `diagnostic-baseline`: original worker, timeout120s. The first stuck call is
  13,561, typed/relevance=true/projection=false/dependency=true, an equality.
* `diagnostic-projection`: projection-first control solves that equality but
  times out at a later product comparison (call13,957).
* `target-plain`: no-dependency-first control times out at another conversion.
* A trial fair scheduler tried all six existing strategy combinations in
  rounds of 256,512,... eqwhnf steps, restarting fresh closures each time.
  Its mock scheduling/exception/overflow tests passed, but `target-scheduled`
  still timed out, now on a common product comparison (first call1118).
  Therefore the scheduler was **removed**, not promoted.
* With that trial scheduler, increasing congruence depth to4096 (`target-deeper`),
  simultaneous same-reference delta (`target-simultaneous`), disabling optional
  singleton probes (`target-no-unit`), enabling the pre-existing experimental
  deep structural comparison (`target-deep-fast`), giving scalar priorities
  precedence (`target-priority`), and increasing syntactic fast-test budget
  to65536 (`target-larger-fast`) all timed out at120s.
* `target-oracle` unsets the entire dependency heuristic; also timeout120s.
* The diagnostic-only environment branches used for these tests were removed
  from the kernel. `run.py` still records/whitelists their names for historical
  experiment records; do not use these controls for validation or resume.

## Trace evidence

`trace-product` captured call1127 of the scheduler trial. The product compares
equalities about `LinearMap.trace`, on the left using `LieModule.toEnd` and
`LieModule.genWeightSpaceOf`, on the right `LinearMap.restrict` and
`Module.End.maxGenEigenspace`. The tensors carry the same algebraic closure of
a fraction ring via different instance paths. `product-shapes/run.log` has
bounded structural views of the original two product types.

`trace-later` captured scheduler call1160 (a larger allowance), showing tens of
thousands of comparisons of Field/CommRing/Module dictionaries and nested
projections. At trace step65,536: 232 memo hits, 7,428 stores, 6,716 retained,
zero cache clears. Thus the cache is not full; optional probe costs are not the
whole cause. The baseline attachment samples show dependency inspection and
singleton witness relocation/quotation; those may be secondary costs.

No conclusive root-cause repair has been found yet. Keep investigating on the
proof-preserving prefix before trusting differences in the abstracted slice.
The eventual validation must include regression gates and independent checks,
then resume the existing 25M checkpoint chain without assistant monitoring.

## Pending syntactic-stack candidate, 09:30

The working `conversion.ml` now has a small unbuilt `fast_stack_test` hint:
the projected-wrapper congruence guard permits ordinary stack conversion when
all arguments are already syntactically equal. Stack normalization is bounded
to 128 combined frames/arguments and comparisons share 1,024 nodes. It does
not itself return conversion success. This candidate is **not validated on the
target**. The active proof-prefix worker is still the original `11acf908...`.
Private witness and closure suites pass; `test-fast-stack.sh` passes regrouped
arguments, relocation, projection/shape rejection, and bounded DAG traversal.

One further hypothesis (not implemented): Lean's `cheap_proj` WHNF preserves
matching projections so `lazy_delta_proj_reduction` can compare their sources
before evaluating fields. Rocq exposes a stuck projection as a `Zproj` stack
over `FFlex`, while its projection-source congruence is in the `FProj/FProj`
branch. Investigate whether source comparisons are being missed for matching
projection stacks. Any speculative source comparison must remain bounded and
fall back to ordinary field reduction for unequal records with equal fields.
