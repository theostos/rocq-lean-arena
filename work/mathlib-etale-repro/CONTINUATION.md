# Etale conversion timeout, 2026-09-15

New reported production failure at original NDJSON line 31,651,932:
`Algebra.exists_etale_bijective_residueFieldMap_and_map_eq_mul_and_isCoprime`.
The 1,800-second declaration timeout fired, not the memory guard. Production
is paused, with the sealed 30M checkpoint intact. The previous v13 candidate
passed all 18 qualification stages and was actually promoted; its Char and
Riemannian successes remain valid evidence, not proof of a full Mathlib pass.

Baseline worker: `9b79edfbe2e46420dda16da40e52793faa27dddb29e28420c583db672d773a00`.
Baseline checker: `273b7adfa2213c572529f1119235e0a20153a570b65b3b63dac1088e80ebb8c7`.
Copies: `baseline-worker.exe`, `baseline-rocqchk.exe`, `baseline-conversion.ml`.
Importer: `../kernel-alignment-pass/importer.1lqiqwaI`.
Production log: `../mathlib-alignment-5m-20260913-with-terminal/attempts/20260915T184325092172Z/MathlibTo35000000.run.log`.

Investigation started at 23:27 CEST. No kernel fix yet. `make-slice.py` is
extracting a dependency slice with **every proof retained**, no abstractions.
Its source and outputs are hashed in `slice.json`. `run.py` reuses the existing
guarded replay harness with a 16GiB/no-swap limit and 3GiB reserve. Unrelated
Lean experiments must remain untouched. Production resumes only after a
candidate passes targeted and regression checks, from the sealed 30M prefix.

Sampled stacks repeatedly enter same-head argument congruence and ordinary
delta unfolding. Lean 4.29 uses a symmetric expression-pair failed-shortcut
cache in `lazy_delta_reduction_step`; this Rocq candidate keys the corresponding
cache by mutable closure identity plus context. Misses on rebuilt equivalent
closures are a hypothesis to test, not an established root cause.

Pinned Lean source:
https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp

No proof-checking flag, equality rule, timeout, or memory budget has changed.

At 23:36, slice extraction completed: 3,140,948 NDJSON records, zero
abstracted proofs; target legacy-export range [3,140,944, 3,140,945).
`baseline-slice` is running unchanged v13 with conversion-entry and typeops
counters. There is no new kernel candidate yet. `projection-diamond.v` is an
additional general test design, not yet executed or claimed to reproduce.

Read-only review found a second hypothesis: Lean's `lazy_delta_proj_reduction`
selects fields once source delta exposes constructors, before comparing other
fields. Rocq's optional projection congruence compares complete sources, and
its unbounded ordinary strategy disables that optional congruence first.
Projection stacks and nodes both need consideration; simply enabling the old
flag is not the same algorithm. Exact replay evidence is still needed.

At 23:57, baseline slice still progressing (~2.47M of 3.14M slice lines).
No main kernel or binary modified. A candidate exists ONLY in
`candidate-conversion.ml`: split same-head congruence at primitive projection
boundaries, checking source arguments before the projected method arguments.
Within each segment all existing right-to-left checks, masks, lifts and
universe handling remain unchanged. Ordinary stacks delegate unchanged.

`test-projection-segments.sh` passes ordering/mask/continuation/failure tests.
`test-projection-order-api.sh candidate` checks real well-typed terms using
Safe_typing/Typeops, including both directions, open binders, and rejection of
different used arguments/selected methods. Logs `projection-api.3NGZvJqa`.
At depth 8192, baseline `projection-api.FptZHyEg` took 13.506s and allocated
9,673,681,392 bytes cumulatively (not resident), whereas candidate took 0.0005s
and allocated 246,352 bytes. This is unnecessary reduction of a discarded
argument, NOT yet evidence that this change fixes the production theorem.
The earlier small-depth observation of constant conversion-step count was
misleading: reduction inside one step can be large. Allocation/CPU counters
expose the difference. No test removes proof checking or alters safety limits.

Cache observation (`test-cache-observation.sh`): failed-shortcut cache hits on
shared closure identities (99/100), misses on reconstructed equivalent closures
(0/100), and is ordered (98/100 on alternating directions). This is another
hypothesis, not proven as the production bottleneck; no cache code changed.

00:04: Baseline slice failed by its 120s declaration timeout at exactly
3140944 (original 31,651,932). Total replay 1656.379s, peak cgroup ~1.33GiB.
Long fallback was conversion call 331977, `Polynomial_MonicDegreeEq/3` versus
`Subtype/2`, dependency preference false; earlier bounded attempts 331975/6.
Native regression `projected_argument_order.v` also times out at its first
Qed on baseline. Initial hyphenated filename attempt was a naming error, NOT
evidence; proper baseline is `baseline-native-valid-name` (5.441s, timeout).

00:08: Applied candidate to actual kernel conversion.ml, plus an observational
`ROCQ_DIAGNOSTIC_CONVERSION_TRACE_HEAD` selector for ordinary fallbacks (no
checking policy change). Rebuilt worker/checker/plugins and ABI-only importer.
Candidate worker: ff724273b82df32df7121413c52b89ffdf4681e084d2eeaeec2d6dd6064b0f55
Candidate checker: 98f836d63942e3904e8acce78247768b321f09eebc5d033b253aa7dfb3300223
Consumer: ../kernel-alignment-pass/importer.WgVIbhEO (lean.ml matches v13).
`candidate-native-v1` passes all three positive and the negative native test,
0.559s whole process. Lean 4.29 commit98dc76e checks corresponding explicit
proofs in ProjectionOrder.lean in0.53s (-j1,-M512,2GiB address cap).

`candidate-slice-v1` now reruns every dependency proof and target with the
same 120s declaration timeout,16GiB cap,3GiB reserve, no abstractions. Trace
head selector records the slow fallback if it remains. Main kernel and run.py
must not change while this pinned replay is running. Production still paused.
Earlier source-only benchmark/mask/open-binder/negative tests all pass; actual
production theorem NOT fixed/validated yet. Regression script
../kernel-alignment-pass/test-witness-candidate.sh is running separately
(1GiB OCaml unit executables, no concurrent Rocq compiler).

00:37: v1 full slice also timed out at the target (120s). The projection-order
change helps the synthetic reproducer, but does NOT fix the production theorem.
Its updated private suite passed; an additional mismatched-later-field foil
then exposed a performance regression: v1 allocates153MB vs baseline582KB.
Staged candidate2-conversion.ml adds a complete projection-name precheck;
that foil now allocates580KB and passes. Candidate2 API tests also all pass,
including depth8192, both directions, open binders, and negative cases.
Candidate2 is NOT applied to main kernel. No candidate is qualified to promote.

The exact trace shows repeated conversion of commutative-ring hierarchy
instances, after Polynomial_MonicDegreeEq expands to Subtype. Remaining
hypotheses include projection-source comparison and redundant unfolded
structure comparisons. Do not equate the synthetic speedup with a fix.
EtalePrefix.v/EtaleTarget.v split the SAME proof-preserving slice immediately
before the failing theorem, so subsequent diagnostic candidates can reuse all
checked dependency proofs instead of repeating25minutes of dependency checking.

Qualification scripts validate.py/check.py/run-small.py/resume.py/finish.py
are prepared but NEVER launched. resume.py and finish.py are hardcodedv1 and
must be updated for a future qualified candidate; DO NOT launch them forv1.
They include19 serial stages and an original-order replay from sealed30M.
The production run remains paused; all sealed checkpoints and logs intact.

01:04: proof-prefix completed with every dependency proof retained and checked,
1575.682s, moduleEtalePrefix, voSHA43773cc43aa38042e07da86950b54d286608e3a896764b1e41454326a3283474,
compiled byv1worker ff724273.... All main kernel sources/binaries were left
unchanged until that pinned compile completed.

Candidate3 now applied to main conversion.ml: candidate2 projection precheck
plus Lean-style symmetric single-delta unfolding on otherwise unpreferred
equal-priority global definitions. Existing direct-occurrence, constructor,
wrapper, compact-elimination and decisive priority preferences remain. The
ordinary non-heuristic API keeps its former one-sided scheduling. Both-side
reduction is beta/iota/zeta after one delta, NOT full normalization. Explicit
Unfold_left/Unfold_right/Unfold_both variants replace a Boolean decision.
unfolding_order_test.ml now tests all three outcomes and prior probe order.
Permanent mismatched-field regression was added to the private suite/gate.

All candidate3 source-only private tests passed, including negative/open-binder
projection cases. Nested let-bound record fixture saves work but is NOT a
pathological reproducer and does not establish the theorem is fixed.
Main rebuildworker/plugins/checker/importer all succeeded.
Worker5d0dc973fb40ebbe10f6518769863ac8d02a3d301daf94ecf0034ac81f4383d8
Checker00c2f7951762fffdbadc97fa7cb6dd086375a335dc95d70cced1e6ef400b4ba4
Consumer../kernel-alignment-pass/importer.KAPimmin (lean.ml identical tov13).
Active target-only replay: candidate-target-v3 (unified session54604),
EtaleTarget.v, --native --prefix proof-prefix --entries, tracehead
EtalePrefix.Polynomial_MonicDegreeEq/3. Main private suite is being rerun too
(session5622; candidate-v3-main-private-tests.log). Do not change binaries or
run.py during the pinned replay. No production launch/qualification queued.

01:27 update: v3 and v4 exact target replays both timed out at120s. v4 adds
bare_projection_stack to avoid bypassing source congruence for unapplied
projections; applied methods still bypass to expose discarded arguments.
A diagnostic projection-first v3 replay passed the first MonicDegreeEq
comparison but exhausted a later bounded attempt and timed out too. This is
diagnostic evidence only, not a qualified production setting.

Main source now contains v5 lazy_projection_sources, adapted from Lean's
lazy_delta_proj_reduction. It lazily unfolds source constants and stops to
select fields when a constructor appears, avoiding equality of unrelated
record fields. It uses existing budgets, transparency, lifts and universe
state; untyped conversion compares every argument without masks or positive
source caches. New helper only applies to matching bare projections with
the Lean heuristic enabled; existing continuations/fallbacks are retained.
Worker/plugins/checker/importer builds passed; fresh consumer importer.ct86AB6s.
Active target-only replay candidate-target-v5 (session10660) has passed the
original slow MonicDegreeEq comparison and progressed further, but no complete
theorem success yet. All private tests passed, including new checked
lazy_projection_test.ml with positive/negative and open-binder cases, both
typed and conservative APIs. Allocation for discarded1024-step payload112960B.
Last log candidate-v5-private-tests-lazy.log. Do not change main source/binaries
or run.py while the pinned replay is active. Production still paused. Existing
finish.py/resume.py remain obsolete hardcodedv1 and MUST NOT be launched.

01:36: v5 exact target PASSED with unchanged production1800s allowance:
candidate-target-v5-production-budget/result.json, exit0,240.591s including
load/save, peak1424780KiB. The120s diagnostic did time out; no production
timeout was increased. Independent rocqchk passed185.867s, same directory's
independent.json (reuses the prefix; not a complete dependency recheck).
Worker f63317ae56bf0a2b9451407b96d160be06cf251360a08e937d7a3f97b5d78e14
Checker af36ea10b64f65d4d3de0638c5951dd1f9b78331c72cd3346d26e46657821c48
Consumer importer.ct86AB6s; lean.ml unchanged from v13.

Private suite with new lazy-projection transparency/negative cases passed.
Extended projected_argument_order.v with bare-projection positive/negative
cases; native run candidate-native-v5 underway. Main source snapshot
candidate5-conversion.ml is byte-identical to actual conversion.ml.

finish.py/resume.py NOW updated to v5. finish requires passing target compile
and independent check, then fresh full slice,19 validation stages and guarded
resume. Qualification EtaleWhole/MathlibTo35000000 now match production's
1800s declaration limit. No other checking flags changed. test-qualification.py
and Python compilation passed. The batch has NOT launched as of this update.

01:36:39: native candidate-native-v5 PASSED0.613s. Launched detached unit
rocq-mathlib-etale-validation-v5.service, active/running, mainPID3470955.
It runs finish.py with the above v5 worker/checker pins. Do NOT modify kernel
sources, binaries, candidate scripts/tests or importer while qualification is
active: hashes are checked throughout. Progress files:
finish-status-etale-v5.json, candidate-slice-v5/run.log, then
validation-etale-v5/progress.json. Source budget matches production1800s.
Production is NOT resumed yet. It resumes automatically ONLY if full slice
and all19 stages pass, using rocq-mathlib-alignment-5m-etale-v5.service from
30,000,001. No recurring production monitoring. All checkpoints retained.

## 2026-09-16,08:33CEST: discarded-parameter repair, v7

The v5 batch stopped at gates after its fresh full slice passed. Existing
DiscardedParameters.v timed out at its first5-second Qed. No production resume.
User asked to fix this regression. The same native fixture now lives in
test-suite/success/projected_discarded_parameters.v and is first in gates.py.

v6 unconditionally restored projected-wrapper preference in both conversion
routes. The discarded-parameter test passed, but the exact Etale replay again
stalled on its first MonicDegreeEq fallback. Only our diagnostic worker was
manually stopped after185.591s (result exit255). It was NOT an OOM or timeout.
Snapshot candidate6-conversion.ml retains that rejected source.

v7 adds same_forwarded_projection_source: same fully applied transparent
constant/universe, same projection, direct constructor result, selected field
Rel/primitive-projection chain ending in Rel, already syntactically identical
forwarded source argument with proper argument-frame-tail relocation. This
selects ordinary unfolding, never proof acceptance. Both ordinary projected
stacks and lazy_projection_sources use it. Unrelated inheritance paths retain
v5 congruence; no timeout/budget/semantics changes. No cClosure edits this turn.

Current worker43e004e329587d3669ddd99c153e7220ee710a9e21fcf77909b68c00bfa80227.
Checker446d7476850ade7055dca801a97aaa3eeb1c66abc7049d9eeba53d0119488432.
Consumer../kernel-alignment-pass/importer.eZWQ15ef, lean.ml byte-identical tov5.
discarded-candidate-v7 PASSED0.561s; candidate-native-v7 PASSED0.606s.
candidate-target-v7-production-budget PASSED230.572s, peak1,600,644KiB.
Private suite PASSED (candidate-v7-forwarding-tests.log). Shift tests explicitly
construct FRel via subs_id2; inject(Rel) is an environment RelKey instead.
Independent target checker is still running as of this entry.

finish.py/resume.py/test-qualification.py now targetv7, require19nativefixtures,
and use the new consumer. Python compilation, qualification-plan assertions
and kernel diff--check passed. No batch launched yet. Before launch, wait for
independent target success. Scripts then run fullslice,19qualificationstages,
and conditional resume from sealed30M. All previous receipts/checkpoints kept.
Do not run Dune concurrently with private OCaml compilation (file race).

08:33:29CEST: independent v7 target PASSED180.340s (prefix/foundation reused).
Launched rocq-mathlib-etale-validation-v7.service, PID403512, startup confirmed
active/running; finish-status-etale-v7.json says running/full_slice. Fullslice,
all19stages, promotion-check then conditional resume. Production still paused.
Do NOT edit pinned sources/tests/scripts/binaries while this batch is active.
Limits unchanged16GiB/no-swap+3GiBreserve;~24GiBMemAvailable,15GiBdiskfree at
preflight. Other Lean jobs untouched. No checkpoints removed. No recurring
production monitoring. User-visible status is finish-status-etale-v7.json,
then validation-etale-v7/progress.json, and candidate-slice-v7/run.log.

## 2026-09-16: stage7 aggregate timeout repair

v7 fullslice PASSED, first6/19qualification stages PASSED, including all19native,
20legacy,44importer and206runner tests, strict-native/policy, Etale-independent,
and original-order30M-to31,651,932. Stage7 original-independent exited124 under
check.py's1800s WHOLE-LIBRARY timeout. The reported slow proof DID finish; later
Polynomial.UniversalFactorizationRing declarations were checking at cutoff.
No type error/OOM. Production never resumed; sealed30M remains intact.

User requested fix. NO kernel/worker/checker/importer modifications this turn.
Added scripts/checker_progress.py: inside existing guard, own checker session,
selectors-driven deadline keyed only to new target constant-start messages,
not chatter; bounded parser; startup/finalization/stalls remain timed; actual
exit status controls success. Budget1800s per progress interval comes from
production plan. Emits atomic progress JSON with current declaration/timing.
Added9unit/integration tests; full215runner tests PASS,2existing skips, receipts
deadline-tests.json/log. Actual native smoke under1GiB guard PASS0.209s,6constants,
deadline-native-smoke.json/log. Production heavy guard remains16GiB+3GiBreserve.

Preserved old scripts/evidence to keep every old input hash valid. New files:
check-progress.py writes original-etale-v7/independent-progress.{json,log} plus
independent-progress-status.json. validate-v7-progress.py verifies ALLoldinputs,
reuses ONLYfirst6successful stage records, reruns stage7then8–19 sequentially.
resume-v7-progress.py requires all19stages, new deadline-policy/progressreceipt,
new runner tests, and the unchanged comprehensive promotion guard.
finish-v7-progress.py orchestrates validation→promotion-check→conditionalresume.
Statusfiles finish-status-etale-v7-progress.json and
validation-etale-v7-progress/progress.json. Originalfailedstage7 remains archived
in place, not rewritten as success. Reusedstage labels/exitstatuses are checked.

Before launch: all215tests and actual guarded smoke passed; v7worker/checker
hashes unchanged, alloldvalidation input hashes verified. No active jobs from
our pipeline;24GiBMemAvailable,14GiBdiskfree. Unrelatedexperiments untouched.
As with prior batches, do not edit pinned scripts/sources/binaries while active.

13:01:05CEST: launched rocq-mathlib-etale-validation-v7-progress.service,
mainPID984184. Startup confirmed active/running. Newvalidation has6verified
successes retained and is running original-independent (stage7) via
check-progress.py. Production not yet resumed. Newchecker progress file appears
after immutable-artifact/seal preflight and memory admission complete.
