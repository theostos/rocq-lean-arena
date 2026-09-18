# Reconstructed-closure conversion caching

Current status (2026-09-16): the combined sharing-aware candidate is integrated,
the private regressions and complete diagnostic proof passed, and fresh V9
qualification is running. The V4/V8 results below are historical measurements,
not the current release. Full Mathlib verification has NOT completed.

This investigation addresses the original-order proof
`isIntegral_of_isIntegralElem_of_monic_of_natDegree_lt` (NDJSON line 31,345,002),
not just the later Etale theorem. The v7 independent checker passed that proof
in 1,097.535 seconds, but its enclosing segment exceeded the old whole-process
30-minute validation deadline. A progress-aware deadline made validation finish;
that was not an algorithmic performance fix.

## Lean comparison

Reference: the locally pinned Lean 4.29 kernel at commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740`, under
`../mathlib-riemann-sharing-repro/lean-4.29-reference/`.

- `type_checker.h`: checking state owns expression-keyed inference, weak-head
  reduction, unfolding, failed-congruence and established-equality caches.
- `type_checker.cpp`, `quick_is_def_eq`: consults `m_eqv_manager`.
- `type_checker.cpp`, `is_def_eq`: records successful expression equality.
- `lazy_delta_proj_reduction`: compares sources lazily and selects a requested
  field once a constructor is exposed; it does not require all fields to agree.

Rocq uses mutable reduction closures instead of Lean's immutable expression
representation. A cache keyed only by closure identity cannot recognize the
same suspended expression reconstructed in a fresh cell. The observed Algebra,
Subalgebra and RingHom comparisons repeatedly traverse overlapping inheritance
structures. One baseline conversion alone exceeded eight million conversion
steps. Merely caching projection-source successes did not fix this case.

## Candidate and correctness conditions

`suspended4-conversion.ml` extends the existing completed-conversion cache with
an index for `FCLOS(template, substitution)` pairs. It captures the templates
and substitutions before reduction, and stores an entry only after the usual
conversion succeeds. Templates are immutable and compared by physical identity.
Hashing never observes mutable closure contents. Where reduction has already
occurred, key selection uses the existing saved original-expression view.

A hit requires the same ordered CONV/CUMUL problem, both lifts, and physical
identity of all three local-context components (relevances, local types, and
their lifts). The existing bounded, read-only syntactic comparison must also
establish that both captured substitutions denote the same expressions as in
the stored successful comparison, including their universe substitutions.
The substitution comparison also uses saved original-expression views, before
traversing potentially large expanded values. These are the reduction machine's
existing pre-reduction snapshots, not newly quoted or normalized terms. The
ordinary fast syntactic test keeps its previous behavior; only the new cache's
lookup opts into this read-only original-expression comparison. The same node
budget covers both original and reduced representations. An inconclusive lookup
falls back to ordinary conversion.

The cache remains local to a checked conversion with a fixed environment and
universe graph. Constraint-generating generic conversion does not enable it.
No theorem-specific names or mathematical assumptions enter the implementation.
The physical and suspended indexes share the existing 32,768-entry allowance.
No production timeout, memory cap, cache capacity, proof, or checkpoint changes.

Tests cover fresh closure cells, different captured values, rejected unequal
terms after a successful cache entry, universe substitution, ordered conversion
problem, lifts, local contexts, fresh conversion calls, disabled memoization,
and shared bounded retention. Two additional regressions specifically exercise
captured values that have reduced since the cached check, and two separately
expanded, well-typed 1,200-field records with identical saved input syntax. They
fail the earlier lookup implementations and pass the current one. Different
computed values remain rejected; the ordinary bounded syntactic probe is
unchanged. Existing unit-like/projection/unfolding/quotation private tests also
pass. The whole stored proof and fresh integrated validation must pass before
this candidate is considered a production fix.

The first complete candidate (V2, without saved-view lookup) passed the exact
stored proof in 932.554 CPU seconds (1,016.037s including loading and hashing),
with a peak guarded scope of 5,133,268KiB. That is only a partial improvement.
The V3 diagnostic was deliberately stopped after its slow first comparison;
its exit255 is cancellation, not a theorem-checking failure. V4 is the ongoing
full-proof diagnostic, under the same 1,800s/12GiB allowance. It subsequently
PASSED in 844.594718 CPU seconds (918.184827s including loading/hashing), with
peak guarded scope5,129,416KiB.

The V4 algorithm was integrated into the main conversion implementation; shared cache
eviction/accounting was factored into helpers without changing lookup rules or
capacity. Integrated private tests and rebuilt worker/checker/plugins pass.
Its qualification ran under
`rocq-mathlib-integral-cache-v8.service`; it used the original whole-segment
independent-checking timeout and resumes the sealed30M generation only after
every gate passes. This attempt was later superseded by V9 as described below.
Full Mathlib acceptance remains unproven.

The rebuilt production worker's exact Etale replay also PASSED. The same import
transaction took68.092s versus220.157s with v7 (complete runner80.511s). This
speedup is from the cache change, not a larger timeout or resource allowance.
The exact target's independent checking also PASSED in26.555s. The remaining
qualification is still running; production resumes only on complete success.

The diagnostic loader reuses library environments and checks only the named
stored proof. Its results are not whole-library validation or a production
receipt. `CONTINUATION.md` records the current experiment and run state.

## Shared-graph follow-up (September 16, integrated; qualification pending)

Three additional gaps are now covered by isolated candidates and regressions:

1. Opening a multi-binder lambda creates a fresh `FLambda` tail without the
   original `FCLOS` view. Successful conversion caching now also recognizes
   that immutable lambda template and its captured substitution. The same
   ordered problem, context, universe, and relocation checks remain mandatory.
   This complete stored-proof experiment passed in767.758CPU seconds versus
   V4's844.595, not an elimination of the overall bottleneck.
2. A bounded structural probe previously revisited shared children as a tree.
   An operation-local memo of completed positive subcomparisons makes the
   independently allocated depth40 test pass in122 of the unchanged1024
   visits. Keys distinguish substitutions, universe instances and relocation.
   Neither failed nor in-progress comparisons are remembered; closures are
   never reduced or modified by this probe. Expanded closure DAGs and200
   deterministic differential checks also pass.
3. The public conversion entry point performed a separate unbounded tree-like
   alpha comparison before reaching that probe. This still timed out on the
   same depth40 fixture. A sharing-aware initial shortcut now uses the existing
   head/universe comparators, with ordered CONV/CUMUL and argument-count keys.
   Its1024-visit allowance is an optimization bound, not a rejection criterion:
   exhaustion delegates to normal conversion. The public conversion test and
   differential tests against the former alpha comparators pass. This also
   tests cumulativity in both directions, casts, binders and independently
   allocated checked bodies with case expressions.

The comparison to Lean is specifically its `equiv_manager::is_equiv_core`
sharing-aware structural traversal and its checker-local successful equality
state, at the pinned98dc76e revision. We are not copying transitive semantic
equivalence classes across Rocq's mutable closures or local environments.
The new probe caches are scoped to a single read-only comparison; semantic
conversion caches retain the existing fixed-universe and exact-context rules.

`suspended8-conversion.ml` combines these changes. Its complete stored-proof
check PASSED in812.774544CPU seconds,893.582842wall seconds, with guarded peak
5,137,428KiB. This is only a modest improvement over V4's844.594718CPU seconds;
the extra DAG memos add overhead relative to the lambda-only experiment.
The decisive evidence for them is the exponential-case regressions, not a
claim that this real proof is now fast. It remains a roughly13.5CPU-minute check.

The candidate is now integrated in `kernel/conversion.ml` (only the extra final
blank line of the isolated source was removed). The complete integrated private
suite PASSED, including the three new regression families. V8 qualification
was deliberately cancelled before completion and superseded, not treated as a
failure or promoted as complete. V9 freshly builds the worker, independent
checker and ABI-only importer, then checks the exact target, the full dependency
slice and every qualification stage before resuming the sealed30M checkpoint.
Service: `rocq-mathlib-integral-cache-v9.service`; initial status:
`prepare-v9/status.json`, then `../mathlib-etale-repro/finish-status-etale-v9.json`.
No timeout, RAM allowance, semantic conversion-cache capacity, checkpoint,
proof or axiom was changed.
Passing these regressions does not establish that all100,001,405 Mathlib
records check; that requires completion of the production run itself.
