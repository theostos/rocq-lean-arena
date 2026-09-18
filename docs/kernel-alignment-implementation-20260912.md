# Kernel alignment implementation — 12 September 2026

Status: validation in progress; **not a full Mathlib pass or a claim of exact
kernel equivalence**. This follows the source audit in
[the review](kernel-alignment-review-20260912.md). That report is a historical
snapshot; its “not executed” findings now have the evidence below.

Current evidence, distinguished by build:

| Item | State |
| --- | --- |
| Previous Mathlib generations | Retired at the user's request: 37 compiled checkpoint artifacts deleted (6,710,183,007 bytes); sources, exports, logs and seals retained as historical evidence |
| Reported line 21,660,881 | Passes; latest measurement: 88.09 CPU seconds on `5fed2fe6...` during `full-shared-budget` |
| Next failure, line 21,692,183 | Passes original-order `full-shared-budget` on `5fed2fe6...`, including the completed 22M save |
| Fully passed gate | `final-gates-20`, worker `938cf20b...`: 13 native, 20 legacy, 44 importer fixtures, runtime/private tests, fresh smoke save/reloads, 204 runner tests passed (two skipped); independent native checking passes in compatibility and strict-with-explicit-UIP profiles |
| Current runtime | `938cf20b...`: bounded constructor-case reduction in type queries repairs match-computed singleton types. The exact `WithTerminal.instCategory._proof_2` proof-preserving slice passes including save (10.99 s), then independent compatibility checking (78.58 s). Original-order replay through 11.5M passes including save (254.23 s), then fresh reload/save passes (36.24 s). |
| Strict imported-artifact limitation | The imported slice is **not** strictly certified: strict-with-UIP rechecking refuses `Slice.autoParam` because the existing importer records disabled elimination checking. No checker policy was weakened. Native strict checks pass separately. |
| Latest regression | The gate-19 fresh generation passed 5M and 10M save/reloads, then failed at 11,422,301. Ordinary type-level cases were declined by the optional inspector. See [WithTerminal evidence](../work/mathlib-with-terminal-repro/README.md). |
| September 13 regression | Fresh gate-16 generation failed at 5,816,190 (`liftToDiscrete._proof_5`), after a successful 5M save/reload. `eef8700b...` passes the proof-preserving slice, exact target, continuation through 6M and gate 18, but fails independent rechecking under binders; `b0239691...` fixes that additional discrepancy. See [regression evidence](../work/mathlib-lift-to-discrete-repro/README.md). |
| Previous diagnostic runtime | `5fed2fe6...`: original gate passed, but expanded eta/saturation negatives fail; its large replay is not a final validated candidate |
| Full 21M–22M replay and reload | `full-shared-budget` passes including save in 1,977.02 s; reload/save passes in 421.34 s; diagnostic artifacts only because expanded correctness tests fail this build |
| Fresh line-1-to-EOF Mathlib generation | Restarted September 13 after the WithTerminal repair in `work/mathlib-alignment-5m-20260913-with-terminal`, service `rocq-mathlib-alignment-5m-20260913-with-terminal.service`, from line 1 with no seed; 5M interval and existing resource limits retained. Full acceptance remains pending. |

The failed September 12 run used the gate-16 worker. The first September 13
replacement used gate 19 and passed 10M before the WithTerminal failure. The
new replacement uses the gate-20 worker and isolated importer `importer.lFy9zJVL`,
rebuilt from unchanged sources for the updated CClosure interface digest.
Runner configuration checks pass: 206 tests run, 204 passed and two skipped.
The service has `Restart=no`; its ordinary model-free progress/resource logging
continues, but no assistant monitoring or automatic agent repairs are scheduled.
Approximately 7 GiB remained free at the latest restart; the disk guard can stop the run
before EOF if headroom becomes insufficient.
The deletion audit is
`work/kernel-alignment-pass/mathlib-checkpoint-cleanup-20260912.json`.
Old artifact hashes and replay measurements below are historical: deleted
snapshots are no longer resumable and can only be recovered by rebuilding.
Full corpus acceptance and the remaining assurance obligations are still open.

## Reference and contract

The completed diagnostic 22M artifact is
`b8c28d98789cc7f65264663c68db489aa7ad2b52d45d09b41baac511e69998dd`.
Its successful save does not retroactively validate newly exposed direct-API
counterexamples or independently recheck the historical 21M prefix.
The same-worker reload/save artifact is
`21d67758ee5036f56006daa55ade8b576af8407f8851f32c3587e14f560596ed`,
with cgroup peak 9,102,756 KiB. The replay and reload workers both exited before
runtime integration of the further source candidate began.

The source export uses Lean 4.29.0, commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740`, not the newer local Lean checkout.
The Rocq base is `f756383de2e66f63c95815c73838596d7d97c1c2`.

The target is preservation of translated Lean judgments with controlled resource
use. It is not identity of the native theories: Lean `Prop` is translated to
Rocq `SProp`, the foundation enables definitional UIP, and quotient/recursor
bridges are explicit parts of the translation. The existing recursive singleton
shortcut is a broader target conversion rule than the reference Lean probe
accepts. Its justification must remain separate from corpus acceptance.

Two reference principles guide the changes: Lean's unit comparison checks full
types, and its term transformations preserve sharing with operation-local,
binder-aware memoization. See the pinned
[type checker](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp#L1046)
and [replacement machinery](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/replace_fn.cpp).

## Executed diagnosis of the latest failure

The 80-frame sample showed substitution/quotation, but omitted its initiating
caller. A deeper replay identified `same_unit_like_flex_rel`: an optional
singleton query was expanding a shared closure into syntax merely to inspect
its type.

| Replay | Result |
| --- | --- |
| Prefix 21,000,001–21,660,880 | Pass; 943.56 s |
| Isolated target, before quotation repair | Memory guard, exit 125; 251.06 s |
| Isolated target, quotation memo alone | Memory guard, exit 125; 223.25 s |
| Isolated target, closure snapshots | Pass including save; 695.52 s total |

The passing target is
`AlgebraicGeometry.Scheme.Pullback.ofPointTensor_SpecTensorTo`, line 21,660,881.
It spent approximately 272.24 process-CPU seconds in declaration checking and
peaked at 11,702,136 KiB in its memory cgroup. The saved artifact's SHA256 is
`37dfeaba1c3dea9eaeb85cabc375ffceea12e1c85a1845ac19df3f178c584f1f`.

Quotation memoization alone was insufficient because a later relocation could
still expand the resulting shared syntax. The repair therefore avoids quotation
for general optional type classification, rather than only caching its result.

## Implemented changes and evidence

| Area | Change | Evidence |
| --- | --- | --- |
| Unit registration (C1) | Only definitely irrelevant fields qualify; unknown quality variables do not | Negative registration fixture failed on baseline and passes after repair; positive fieldless/universe and SProp controls |
| Arithmetic sharing (C2) | Do not consume application arguments across a function's update frame | Baseline turned a shared function into numeric zero; shared and partially applied controls now pass |
| Unit operand types (C3, neutral paths) | Compare full instantiated types, retain binder relocations, reclassify the reconstructed common type | Direct API tests cover incompatible parameters/universes, named and bound variables, constructors and local type functions; older typed constructor/mask paths still require a common-type invariant audit |
| Registration order (C5) | Replay persisted actions chronologically; missing prerequisites produce an error, not an assertion | Fresh complete-family module fixture reproduces baseline assertion and passes after repair |
| Arithmetic certificates (C6) | Check the entire abstract universe/quality context, not just type syntax | Phantom-universe builder/operation negative fixture reproduces baseline acceptance and passes after repair |
| Closure quotation | Memoize by closure identity and relocation within one quotation | 40-level application and lazy-substitution DAGs; differing lifts and post-mutation quotation controls |
| Constructor lifting | Preserve the constructor DAG with a per-operation, closure/shift-keyed cache | A 20-level shared constructor fixture drops from 117,440,536 to 6,192 allocated bytes; differing shifts and binder controls pass |
| Optional type queries | Copy a bounded DAG of closure cells/substitutions; isolate mutations and share fuel with head-machine steps | 50-level DAG, ignored substitution, relocation, exhaustion, repeated-call and divergent-beta tests |
| Artifact integrity (C7, partial) | Remove both environment-variable digest bypasses | Matching dependency loads; changed dependency is rejected with the old switch unset, `0`, and `1` |
| Query projection safety | Decline dependent field-type inference with a dummy record; check projection identity and saturation in speculative reduction | Partial constructor, wrong inductive and out-of-range projection queries decline; a matching saturated control succeeds |
| Alias transparency | Remove raw-body alias shortcuts; retain the caller's transparency in an isolated alias table | Baseline accepts the opaque-alias negative test; repaired worker rejects it and passes the transparent control and existing alias regressions |

The snapshot interface declines unsupported computation and budget exhaustion.
It does not return “not equal,” mutate caller-owned cells, or silently approve a
declaration. It is an optional search mechanism, not a complete normalizer.

The first C3 integration replay caught an implementation defect at line
21,071,018 (`HahnSeries.ofPowerSeries_apply`). Quoted open types had been injected
as though all relative variables belonged to the ambient environment. A small
test with an applied local type function reproduced the `Not_found`; preserving
the local identity substitution fixes it. This is why unit tests and an isolated
successful theorem are not substitutes for original-order replay.

The next full-segment replay (`full-witness-context`) passes the reported
21,660,881 declaration in approximately 269.85 process-CPU seconds. It then
exposes a separate query-only projection array access at 21,692,183,
`AlgebraicGeometry.AffineTargetMorphismProperty.IsLocal`. That defect is reproduced
and repaired by the projection checks above; a new full-segment replay is still
required. No completed 22M artifact is implied by passing the earlier declaration.

The earlier worker including constructor lifting was
`2033acd096a6ae60fd3188e501d5c9024930c7d22a3e5c2f9ad034a7c3e9ab2a`.
Its ten native fixtures, twenty legacy fixtures, five unit-test families, digest
negative tests, and a fresh 1,128-line generation with three sealed chunks and
fresh reloads pass. All 44 importer fixtures and 199 runner tests pass (two
additional tests skipped). The independent native-fixture check hits its
180-second timeout; it is not counted as a pass. The verbose retry described
below exposed a conversion-order regression in the conservative checker API.

A subsequent cache repair, now included in the passing final gate, indexes
projection source comparisons by physical closure pair, capped at 4,096 entries and
eight context variants per pair. The successful-conversion cache also caps
context variants. Both keys explicitly retain local type relocations. Private
cache tests exercise hits, misses, changed contexts, and eviction.

An attempted replacement of the common-application congruence probe by closure
snapshots was rejected by integration testing (details below). The candidate
retains that probe's syntax representation, but preflights its expanded size
under one 65,536-node allowance shared by both sides. Compact numerals have a
bounded, exact quotation-cost function; unsupported proof/evar representations
decline before quotation. This does not turn the existing congruence depth
budget into a full work bound; nested mandatory conversion still needs the
broader resource audit. The adjacent export passes this bound in 26.70 s under
a 10-second declaration timeout. The complete repeated gate now passes.

Using the type-query allowance of 4,096 nodes for executable prefixes was
tested first and rejected: it exhausted the budget during compact-numeral
inspection and forced the costly fallback. A separate 65,536-node application
allowance retains a finite expanded-size limit. A 12,287-node synthetic prefix
is accepted; exact boundary, shared-budget, negative allowance and oversized
50-level DAG cases are tested. The type-witness allowance stays at 4,096.

Two nested query costs are also addressed in that candidate: an environment
relative definition's raw lift is preflighted against the shared inspection
budget, and query-only constant lookup skips relevance-mask construction that
its restricted reduction path does not use. A 20-level local-definition DAG
query declines within 128 steps, while the small-definition control succeeds.

The expanded importer gate caught a candidate regression at
`Nat.Linear.ExprCnstr.denote_toNormPoly`: resetting every copied cell to `Red`
violated the fixpoint head machine's state invariant once snapshots were used
for ordinary congruence. The correction retains intrinsic constructor/neutral
marks while reactivating policy-dependent cells. A focused frozen-fixpoint copy
test passes. The failed `final-gates-4` result is preserved; it is not a validated
worker version.

After correcting the shape marks, the snapshot-congruence variant still times
out on the same importer regression (`final-gates-5`). A shortened diagnostic
captures 1,991 native frames in conversion. Restoring the original quotation
representation makes the full adjacent export pass again under the shorter
10-second declaration limit (`adjacent-quotation-control`, 25.57 s total).
Therefore snapshots remain the type-query mechanism, not an unconditionally
substitutable representation for ordinary congruence. The subsequent bounded
quotation candidate is being tested separately. No failing variant is labeled
as a validated replacement.

The verbose independent-checker retry locates its slowdown at
`projected_constant_congruence.Unnamed_thm2`, the wrapper with an expensive
discarded argument. `checker/mod_checking.ml` uses the conservative
`Conversion.conv_leq`, whereas ordinary `Typeops` uses `default_conv CUMUL`.
The candidate makes the **delta-order preference only** available to both
entry points. It does not switch the checker to the typed API, change equality
rules, or skip checking the discarded argument's well-typedness. This repair
passes the independent-checker retry after rebuilding
(`final-gates-4/independent-check-order.json`, exit 0). All ten native artifacts
and their dependencies were checked without `-admit` or `-norec`. The summary
reports no axioms, type-in-type, unsafe fixpoints or assumed positivity; this
is still not the not-yet-implemented strict elimination/theory profile.

### Gate before the dependent-projection repair

`final-gates-6` passes with worker
`796f7179d853be18c7d5b22123f79ae5bcbbef7e7f7881c7c47abeecdc7c6e45`
and the unchanged consumer plugin hash below:

- Ten native kernel and twenty legacy integration fixtures.
- Six runtime unit-test families, plus private projection-cache, expanded
  quotation-budget and compact-numeral cost tests.
- Dependency-digest negative tests, including the removed bypass switch.
- A fresh foundation and 1,128-line small export in three sealed chunks, each
  reloaded in a fresh process. This is a NatBeq export, not a Mathlib prefix.
- All 44 importer fixtures; 199 runner tests pass and two additional tests skip.
- Independent checking of all ten newly compiled native artifacts and their
  dependencies: exit 0, 1.79 seconds, no `-admit` or `-norec`.

The full 21M–22M replay on this build (`full-final`) passes the original target
in 130.08 process-CPU seconds, then fails at 21,692,183 with an illegal application,
not the earlier projection assertion. Total wall time is 753.47 s; cgroup peak
is 9,977,320 KiB. There is no completed 22M artifact.

The follow-up identifies a missing legitimate case: full unit-type witnesses
must infer dependent projection types using the actual record. A type-only
query with a dummy scrutinee must still decline. `dependent_unit_projection.v`
reproduces the failure at `Qed`; a direct conversion test also fails on the
preceding binary. The source candidate carries a copied actual subject through
application/projection elimination and compares complete types. It passes both
directions of the valid direct comparison and rejects a payload type depending
on a different record, also for records returned by a function. The rebuilt
worker passes the native fixture at Qed. The exact Mathlib line passes including
save (`projection-subject`, 466.20 s, peak 8,852,416 KiB), with artifact SHA256
`bae5423767a813de8e4d7a4156fb19f3d9d2bb9031280c01657dd8d7d5b17ed5`.
That worker (`c1419eb7...`) subsequently fails the legacy `AliasControls.v`
negative test in `final-gates-7`: the new full-type query bypassed the old
query's oracle-opacity check. It is **not** a fully validated version.

The correction intersects the caller's reduction transparency with the
oracle's transparency for this optional full-type query. The native dependent
projection fixture now includes the opaque-alias negative and transparent
positive controls. The complete `final-gates-8` passes on worker `a4a85a6c...`:
eleven native fixtures, twenty legacy fixtures, the six runtime unit families
and private tests, fresh small import/reloads, all 44 importer fixtures, and
199 runner tests (two additional tests skipped). Independent checking of the
eleven native artifacts and dependencies passes in 1.80 s. Full-segment/reload
validation is pending. This preserves
the existing optional-query policy; it is not a claim that oracle opacity and
logically opaque declaration bodies are identical concepts.

`projection-prefix` saves the sequence up to, but excluding, 21,692,183 in
556.98 s, using the preceding worker. Its artifact SHA256 is
`1cc035733aa3491c48f822f052ede632af9426abd9bc817a07c41ad69d6e99ce`.

## Checkpoint provenance and validation boundary

The canonical checkpoint chain remains sealed through 21M. Its original importer
binary and producer seals were not overwritten. The new runtime interfaces
required rebuilt core plugins and an isolated importer build under
`work/kernel-alignment-pass/importer.ppBaeRqL`. The later quotation-cost
interface required another isolated build, `importer.brtcQ36Y`; the dependency
query interface now uses `importer.42J4K0w1`. Earlier consumers were preserved.
The current worker SHA256 is
`3a9480ea6f86050019bf78e3be3c0dc254ccb96b4cad361e99af1e862dc637dd`,
and its consumer plugin SHA256 is
`b17738e6278ee0df0984fbdac06653001f1a1d29eb046bb2f241d86f1d5d4cde`.

Diagnostic replays verify the original producer inputs and separately pin the
new consumer plugin/source. They do **not** retrospectively recheck earlier
opaque proofs or authorize rewriting their seals. A new full-pass claim needs a
fresh foundation and generation from line 1.

All large replays retain the 1,800-second declaration timeout, 15-GiB RSS guard,
16-GiB memory cgroup and zero swap. Only one heavy worker runs at a time. No
proof-skipping mode, digest bypass, commit or push is part of this pass.

## Outstanding work before a full-alignment claim

1. Complete the current-build large replay/reload and start a fresh full generation
   when disk capacity is available. The integrated regression and independent
   native-checker gates pass; the preceding-build 22M pass is not EOF evidence.
2. Extend large-corpus validation of bounded secondary dependency queries with
   certified heights. The preceding build passed 21M–22M, and the current
   stricter eta/substitution build is being replayed. The importer already
   provides Lean scalar unfolding metadata;
   coherence of its heuristic overrides still needs workload review.
3. Finish consolidation of all optional-query work accounting, including raw
   occurrence scans and some metadata traversals. The current step budget is
   not a universal bound on every nested OCaml operation.
4. Continue auditing cache keys, universe-state handling and mutation invariants
   beyond the now-integrated bounded projection-comparison cache.
5. Extend the now-tested raw lifting, substitution, universe-instantiation and
   module-substitution sharing audit to remaining generic substitution paths,
   adversarial hash collisions and extreme recursion depth. The tests below
   establish specific repairs, not a universal linear-work guarantee.
6. Complete arithmetic continuation/flag/large-number testing and strict
   independent certificate replay.
7. Specify and check the translation's permitted theory profile. The new strict
   checker policy below rejects disabled safety checks; compatibility mode
   still honors serialized flags. Fresh `Require` is not strict proof rechecking.
   The importer has a conditional elimination-check relaxation which strict mode
   refuses and which must be justified precisely, not hidden by a “strict” label.

Reproduction drivers and chronological evidence are recorded in
[the implementation log](../work/kernel-alignment-pass/README.md). New fixtures
are under the Rocq worktree's `test-suite/success` and
`test-suite/unit-tests/kernel` directories.

## Bounded dependency-graph candidate

The preceding worker still retained transitive dependency bitsets. The source
candidate instead stores complete **direct** edges (65,536 edge/entry weight
cap) and definite source/target answers (8,192-pair cap). An explicit worklist
shares a 16,384-unit default allowance across syntax and graph traversal;
callers can share that allowance across related probes. Exhaustion returns
`None`, never a cached negative. Cycles terminate through visited-node tracking.

Immutable cache maps are forked with each environment. The first candidate
invalidated pair answers on every addition. The revised source retains stable
answers across ordinary extensions, but invalidates on replacement or when
cached negatives encountered missing references. Stability travels with each
answer, including through cache eviction. Replacing a cached direct body clears
the direct cache.
Unmarshalled environments use a query-local cache. There is no all-pairs closure,
global name-to-bit numbering, or syntax retained by the physical traversal memo.

Conversion callers distinguish the meaning of an unknown answer: it cannot
establish compact backing or a dependency preference, and it declines the
optional full-application evaluation path. Ordinary delta conversion remains
available. The existing imported scalar heights remain the oracle metadata;
this is not a new source of trusted equality judgments.

The renamed-module candidate test passes existing semantic, dense-DAG,
fork/replacement/reload and sharing tests. New controls cover partial scans,
both signs after exhaustion, negative/zero fuel, shared fuel on warm hits,
cycles, a 200,000-argument term (about 34 KB allocated before declining),
50,000 distinct pair queries (62,395 retained words on the repeated run), and 20,000 direct-edge
entries/640,000 edge occurrences (145,408 retained words). These numbers are
fixture measurements, not whole-Mathlib bounds. The scan now allocates its
physical memo lazily, avoiding the 4,096-slot scratch table for atomic aliases.
The worker, core plugins, checker and isolated consumer rebuild successfully.
The repeated `final-gates-9` passes: six runtime unit-test families and private
tests, eleven native and twenty legacy fixtures, a fresh small import with
three sealed chunks/reloads, all 44 importer fixtures, and 199 runner tests
(two additional tests skipped). Independent checking of the eleven native
artifacts and dependencies passes in 1.82 s without admitted dependencies or
`-norec`. The strict theory-profile caveat still applies. The original importer
hash was rechecked unchanged after the rebuild.

The host suspended from 18:08:58 to 19:13:12 during this gate, confirmed by
`systemd-suspend.service`; that wall-clock gap is not a kernel-performance
measurement. The resumed arithmetic fixture passed normally. `full-dependent`
replayed from 21M on this worker with diagnostic stack sampling, without using
the mixed-build diagnostic prefixes as its starting state. It was deliberately
stopped after 1,266.99 s (exit 143), around line 21,372,595, because it exposed a
large performance regression. It did not time out on a declaration, report a
checking error, or save a 22M artifact. Logs and samples are retained.

The root-only pair cache repeatedly traversed overlapping dependency graphs,
with fresh additions also discarding prior answers. The revised source consults
cached answers inside graph traversal and caches completed negative DAG
subgraphs in postorder. Incomplete subgraphs never yield cached negatives.
Encountering a back edge disables local negative caching; an exhaustive root
search can still establish a negative even on a diagnostic cyclic graph.

Standalone tests pass for 1,000 new roots sharing a warmed 1,000-node graph,
with only 16 work units per query. Additional controls cover replacement of an
intermediate node, a cycle with an escaping path to the target, and reuse of an
unstable cached answer across an 8,192-entry eviction boundary followed by
definition of its formerly missing reference. `final-gates-10` passes the whole
repeated gate: eleven native and twenty legacy fixtures, all runtime/private
tests, fresh small save/reloads, 44 importer fixtures and 199 runner tests (two
additional tests skipped). Independent native checking passes in 1.80 s.
The public interface and isolated importer remain compatible. The corrected
whole-segment replay, `full-dependency-memo`, was stopped after 872.29 s
(exit 143) around line 21,329,038: dependency search still dominates samples.
It reported no checking failure and saved no 22M artifact. The earlier gate pass is not a performance
endorsement of `4d9c3e39...` on large Mathlib inputs.

Compiling the expanded test against the saved preceding `Reviewed_environ`
object (`dependency-candidate.GmPn2da0`) reproduces the overlapping-query failure
at `constant_deps.ml:326` (exit 2). The corrected module and rebuilt runtime both
pass. Thus this new test distinguishes the two implementations, not just the
intended outcome.

Disk housekeeping removed 155 disposable unit-test executables generated by
this pass, freeing approximately 1.3 GiB. Their sources, object files, scripts
and logs remain; the executables can be rebuilt. No proof artifacts, canonical
checkpoints or old user artifacts were removed.

A later cleanup removed another 91 completed OCaml test executables generated
by this pass (745,151,904 bytes, approximately 0.69 GiB), after validating exact
regular-file paths and that none were running. Sources, object files and proof
artifacts remain. The exact list is in
`work/kernel-alignment-pass/cleanup-test-executables-2.json`; the retained test
scripts can rebuild these executables.

## Rejected scalar-priority unfolding experiments (chronological record)

Pinned Lean's `lazy_delta_reduction_step` follows unequal declaration hints
before its equal-priority congruence/unfolding path; the base Rocq worktree
also restricts its dependency tie breaker to equal oracle levels. The custom
conversion had reversed that precedence: it eagerly computed dependency and
constructor preferences and allowed them to override unequal levels, despite
the importer already installing Lean's heights.

The revised source restores scalar-priority precedence. Dependency and
constructor callbacks run only on ties with the heuristic enabled; a definite
dependency preference also skips the constructor callback. The previously
validated projected-wrapper preference remains before this policy. No equality
or proof-erasure rule changes. This is not an assertion that every imported
oracle override is justified or that equal-priority scheduling now exactly
matches Lean's simultaneous unfolding.

The private test compiles the actual conversion source and puts throwing
callbacks in paths that must not execute; both priority directions, disabled
heuristics, tie preferences and conservative fallback pass. Runtime integration
and large replay are pending. Reference:
[pinned Lean lazy delta](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp#L828).

`final-gates-11` on `aee6367f...` passed the runtime/private tests and eleven
native fixtures, but caught a five-second timeout in the legacy
`direct_unfolding_dependency.v` fixture. It deliberately gives an expensive
function higher priority than its constructor wrapper. Scalar priority alone
is insufficient here: the selected field can be exposed without evaluating
that function. Lean likewise tries projection exposure before unfolding an
expensive opposite-side definition.

The revised wrapper recognizer tests the constructor and selected-field bounds
without inspecting or unfolding the field itself. It remains restricted to a
wrapper applied before a projection, preserving ordinary congruence for methods
of constant dictionaries. Stack and body-spine inspection each have a 1,024-step
bound. No dependency closure is needed for this preference. Before the final
stack-bound addition, `priority-projection-direct` on `b09a95db...` passed both
directions and the unequal-term rejection in 0.54 s. The full repeated gate is
`final-gates-12` on `5440347d...`: eleven native and twenty legacy fixtures,
runtime/private tests, fresh small save/reloads and 28 importer fixtures pass.
The unchanged UTF-8/bit-vector fixture then times out at line 146567 under its
30-second declaration limit. The candidate is not promoted. A focused diagnostic
prefix is being prepared to distinguish ordering from wrapper-congruence effects.

Focused isolation used a fresh 1,950-entry UTF-8 prefix (`utf8-priority-prefix`,
58.82 s), retaining its producer hash and pinning each new consumer. The target
timed out in both `utf8-priority-target` and `utf8-priority-trace230`; separating
the ordering-only broad field recognizer from congruence suppression still timed
out (`utf8-priority-split`, `e7e8fd64...`). The trace shows arithmetic repeatedly
unfolding while the opposite side remains a list lookup. Broad constructor-field
preference is therefore rejected, not treated as a general Lean optimization.

The narrower forwarding/function-field rule is restored, with bounded wrapper
stack/body-spine scans. For unequal priorities, a bounded direct-occurrence probe
may expose a translated wrapper; otherwise the existing constructor-argument
preference is retained before the scalar oracle. Transitive graph queries run
only for actual ties. Direct witnesses alone still timed out
(`utf8-priority-direct`, `54e5c6fa...`); restoring the constructor preference
passes the saved target in 5.04 s including save, under the original 30-second
limit (`utf8-priority-constructor`, `ff8a84ac...`). The direct-dependency native
fixture passes both directions and its negative control in 0.61 s on that build.
This is measured translation-specific scheduling, not a claim to duplicate
Lean's scheduling exactly. The complete repeated gate, `final-gates-13`, passed
the native/legacy/runtime tests, small save/reloads and 23 importer fixtures,
but stalled at `Int32.toBitVec_div` (fixture line 89636). It was deliberately
stopped after approximately five minutes in that fixture (exit 143), without
waiting for the configured 600-second limit. The earlier worker completed the
entire Int32 fixture much sooner. This scheduling candidate is also rejected.

## Certified dependency heights

The source restores the previously validated result priority and constructor-
before-dependency probe evaluation order. Constructor inspection can mutate
closures, so merely reordering those callback evaluations is not neutral.
A private test now checks both the selected result and callback order.

The graph cache additionally retains at most 65,536 certified scalar heights,
computed during completed postorder scans. A dependency edge strictly decreases
height; a source no higher than a known target cannot reach it. This is derived
from actual bodies, not from oracle strategies, which the translation can
override. No additional complete traversal or all-pairs closure is required.
Missing references, cycles, partial scans, overflow and cached negative answers
without a height prevent certification of the corresponding ancestor. Existing
heights survive ordinary additions; replacement invalidates them. Cache eviction
only loses pruning opportunities.

The complete dependency suite passes. A new control warms two independent
1,000-node DAGs, then answers fresh cross-DAG queries in two work units, where
ordinary traversal cannot finish. Replacement, missing-reference, partial-scan
and cycle controls pass. The 20,000-source storage fixture retains 396,354 words,
within its pre-existing 700,000-word cap. A 70,000-node height-eviction control
retains 227,880 words and proves eviction causes a miss, not a wrong answer.
The new two-unit negative test fails against the retained preceding module
(`dependency-candidate.eCdETJsU`, assertion at `constant_deps.ml:373`) and passes
against the candidate.

Runtime, plugins and checker rebuild on `20c123da...`. The isolated UTF-8 target
passes including save in 5.03 s; the complete fresh Int32 input passes in 88.79 s
including save, peak 294,312 KiB. That includes the declaration which stalled
under the rejected ordering candidate. The complete `final-gates-14` passes:
eleven native and twenty legacy fixtures, the six runtime families and private
tests, dependency-digest rejection controls, a fresh small import with three
sealed chunks/reloads, all 44 importer fixtures, and 199 runner tests (two
additional tests skipped). Independent checking of all eleven native artifacts
and their dependencies passes in 1.90 s, without `-admit` or `-norec`. This
checker still does not enforce the outstanding strict theory profile.

`full-certified-heights` replayed the whole 21M–22M segment from the canonical
21M checkpoint, using this exact worker and the pinned isolated consumer. It
was deliberately stopped after 1,374.77 s (exit 143), around line 21,336,923
(`Function.HasTemperateGrowth.comp'`). Memory stayed near 8.6 GiB, but repeated
samples still showed dependency traversal. No checking failure or declaration
timeout occurred, and no 22M artifact was saved. Certified heights alone did
not repair this large-corpus performance problem. No mixed-build diagnostic
prefix was its starting state; the old canonical artifacts' opaque proofs were
nevertheless not rechecked by loading them.

## Raw syntax transformations

Auditing the transformations following closure quotation reproduced additional
tree expansion in the unchanged base traversal algorithms. The following are
standalone measurements of the actual candidate modules, compiled separately
while the large replay keeps worker `20c123da...` fixed:

| Operation, 18-level shared DAG | Old runtime allocated | Candidate allocated |
| --- | ---: | ---: |
| Raw syntax lifting | 16,777,320 bytes | 5,128 bytes |
| de Bruijn substitution | 16,777,568 bytes | 5,352 bytes |
| Named-variable substitution | 16,777,544 bytes | 5,328 bytes |
| Universe-instance substitution | 83,886,224 bytes | 3,424 bytes |
| Module substitution | 161,480,696 bytes | 3,456 bytes |

The old closedness check exceeds the 10-second standalone limit on a 50-level
shared DAG; the candidate completes it and the other occurrence checks. Lifting
and variable substitution cache completed compound results by physical input
and binder depth within one operation. Universe and module substitutions have
fixed parameters throughout traversal and use operation-local physical-input
keys. No cache is shared across distinct substitutions or environments.

The new tests cover differing depths for the same shared term, multiple
substituends, protected binders, successive operations, empty substitutions,
universe and quality/relevance changes, arrays, cases, fix/cofix binder
accounting, unchanged-pointer controls and interruption. Raw lifting is also
compared against the previous tree algorithm on a family of small terms.

Module substitution additionally omitted array elements, defaults and types.
The array-rename test fails on the old runtime and passes on the source
candidate, including sequential substitution. The repaired traversal preserves
module DAG sharing (3,456 allocated bytes in the 18-level fixture) and passes
projection/case metadata and differing-universe controls.

These adaptations follow the reference Lean principles of operation-local,
identity/offset-aware replacement and instance substitution:
[replacement](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/replace_fn.cpp#L14),
[instantiation](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/instantiate.cpp#L13).
OCaml keys use bounded GC-stable structural hashes and physical equality,
not raw moving-heap addresses. Hash collisions can still degrade lookup cost;
the recursive traversal is not claimed stack-safe for arbitrary-depth inputs.
Other paths such as generic `esubst` remain to be audited. This is **not** a
claim that all syntax transformations now have a universal resource bound.

The three new runtime test families are added to `test-quotation.sh` for the
next integrated gate. Runtime rebuilding starts only after confirming all
`full-certified-heights` child processes have exited.

## Accounting for nested dependency work

The 1,024-step indirect-dependency probe used a separate 16,384-unit graph
allowance. Thus the advertised process-inspection budget did not account for
its dominant nested cost. The candidate shares its existing 1,024-unit fuel
with `Environ.constant_depends_on`. Exhaustion still means unknown and leaves
ordinary conversion available; it is not a negative dependency certificate.
The effect on translated arithmetic and large-corpus scheduling must be tested.

The compact arithmetic eligibility probe also searched a constant's dependency
graph before encountering a free relative variable later in the application.
It now completes its bounded, non-mutating closedness/alias inspection first,
then seeks the compact witness. The temporary constant list is bounded by the
inspection allowance. Occurrence order, duplicates and witness short-circuiting
are preserved. A private test checks that incomplete inspection executes no
witness callback, while completed inspection checks candidates in order.
The actual candidate conversion module passes that test plus the existing
witness/cache/quotation/order tests.

These syntax, array and probe changes rebuild successfully in worker
`5fed2fe6...`, with rebuilt core plugins and checker and the same compatible
isolated importer. All nine runtime unit families pass. `utf8-shared-syntax`
passes the saved target including save in 5.02 s, and `int32-shared-syntax`
passes the complete fresh Int32 input including save in 86.28 s. The complete
`final-gates-15` gate passes: nine runtime families, private helper tests, digest
controls, eleven native fixtures, twenty legacy fixtures, fresh three-chunk
save/reloads, all 44 importer fixtures and 199 runner tests (two more skipped).
`full-shared-budget` subsequently passes through 22M including save in
1,977.02 s. The original target takes 88.09 process-CPU seconds. This diagnostic
build predates the further eta/saturation repairs described below and is not
promoted to the canonical generation.

## Explicit independent-checker safety policy

Checker `087f0738de827b1b164c9fa00bfca686dbdcf15e767552fe1e0c405a2dcab726`
adds opt-in `-strict`. Before checking each serialized constant or inductive it
rejects disabled guard, positivity, universe or elimination checking. Serialized
definitional UIP requires the explicit `-allow-uip` option. Strict mode also
rejects `-admit` and `-norec`, regardless of argument order. Compatibility mode
is unchanged. This rejects disallowed saved metadata instead of silently
overwriting the flags and leaving unchecked metadata in the environment.

`strict-checker-1` passes eleven CLI cases using actual saved modules: default
compatibility checks, strict rejection of three disabled-check flags, UIP
rejection/explicit opt-in, and the two admission-option negative controls.
The elimination flag is covered by the direct `CheckFlags` policy unit test,
not by a vernacular fixture. That unit also verifies all four disabled flags
are still rejected after allowing UIP.

The eleven native fixtures and their dependencies are independently rechecked
without admitted dependencies in both profiles: 2.21 s compatibility and
2.13 s strict (`final-gates-15/independent-check.json` and
`strict-independent-check.json`). Strict policy is not a theorem that the two
kernels coincide, an axiom-freedom claim, or a claim that the whole translated
Mathlib satisfies this profile. In particular, the importer's conditional
elimination relaxation remains an explicit outstanding translation obligation.

After this gate, 55 completed disposable test executables (438,635,168 bytes)
were removed. Exact paths and verified absence are recorded in
`cleanup-test-executables-3.json`; sources, objects, logs and all proof
checkpoints were retained.

Two subsequent narrow cleanups removed another 46 completed test executables
(449,239,240 bytes) and 21 standalone test executables (141,415,712 bytes).
`cleanup-test-executables-4.json` and `cleanup-test-executables-5.json` record
exact paths, sizes and verified absence. Sources, compiled comparison modules,
plugins, logs and all proof checkpoints remain; only rebuildable executables
were removed.

## Further record-eta common-type audit (source candidate)

The expanded `unit_type_witness.ml` constructs a primitive `WitnessBox A` and
a registered parameterized `ParamUnit A`. Both operands are individually
well-typed. Comparing `witness_box (ParamUnit A) (param_unit A)` against a
neutral of type `WitnessBox (ParamUnit B)` succeeds incorrectly through the
old eta-field mask. This is a reproduced public-conversion API gap, not an
executed proof of `False`. Lean's pinned `try_eta_struct_core` checks full
operand types before eta (type_checker.cpp, line 752).

The source candidate removes `record_unit_like_mask` and its six call sites.
Singleton-valued fields go through conversion, including the now-checked full
type witness, rather than being skipped from one side's classification alone.
The new test rejects incompatible parameters in both public conversion APIs
and both directions; matching types continue to pass. All existing private
witness, cache, quotation and ordering tests pass with this source candidate.

A second private test covers opaque projections against registered-unit
constructors under the importer's elimination-relaxed compatibility profile.
Default Rocq gives the proof-only relevant record `NoEta`; the explicit relaxed
declaration profile gives it eta. The old conversion accepts incompatible
parameters through a direct `cuniv` return. The new path reconstructs the actual
projected type on a bounded isolated snapshot and checks full types. Positive
opaque controls and both negative directions pass. The saved old candidate
`witness-candidate.CpA50XHl` fails the negative test; the current source passes.
No runtime/profile was weakened to pass this test; the test intentionally
models the existing compatibility profile which strict checking rejects.

These edits were made while `full-shared-budget` ran on unchanged `5fed2fe6...`.
They require rebuilding and re-running the integration gate after that worker
has exited. Its large-replay result is only performance/diagnostic evidence for
the preceding runtime, not a pass of these additional eta repairs.

The same extended test found a saturation gap: a registered-unit constructor
with all parameters but an unsupplied irrelevant proof field was classified as
an inhabitant, although it still has a function type. The constructor witness
now requires exactly `nparams + nfields` arguments and the registered sole
constructor. Both public APIs reject partial constructors in both directions
and accept their fully applied counterparts. A runtime-family regression uses
ordinary checked declarations, without elimination relaxation. Additional
private projection controls cover local binders and function-returned records.

Starting with the next integrated gate, `gates.py` records hashes of kernel,
checker, unit/native fixture and local harness sources in `source-inputs.json`,
and checks them again before recording success. Earlier gates retain their
original records; they do not retroactively certify these expanded tests.

The running replay also samples significant quotation/instantiation work after
the nested dependency cap. One avoidable allocation in the new syntax cache
is repaired in the source candidate: atomic universe-substitution calls no
longer allocate a hash table. Compound traversals still memoize atomic results
too, preserving sharing. The 1,000-sort test drops from 696,096 to 400,096 bytes;
the old runtime fails its 450,000-byte bound and the candidate passes. All DAG,
quality, binder, occurrence and repeated-instance controls continue to pass.

### Precision about the recursive singleton contract

`LeanSingletonContract.lean` proves the propositional equality of arbitrary
`ContractBox (ContractProofBox P)` inhabitants by ordinary constructor
elimination and reflexivity. Pinned Lean 4.29 checks the theorem and reports no
axiom dependencies. The earlier direct-reflexivity kernel probe still rejects
the corresponding neutral equality. Thus the observed acceptance difference
is not evidence of inconsistency: this instance is already propositionally
provable in Lean. It does not prove conservativity or judgment preservation
for a general recursive conversion extension, which remains a distinct
translation obligation. The successful small probe used one Lean thread,
512 MiB internal allocation limit, 2 GiB virtual-address limit and 10 s timeout;
the earlier 1 GiB virtual-address attempts exhausted that limit during loading.

## Sharing inside a closure's raw substituted syntax (source candidate)

An expanded quotation regression constructs one closure containing an 18-level
shared raw syntax DAG and a nonidentity substitution. The previous closure-cell
cache still allocates 71,304,024 bytes, because `CClosure.subst_constr` recursively
revisits that syntax. This is a distinct path from `Vars.subst1` and from a DAG
made of separate closure cells.

`subst_constr` now memoizes completed results by physical raw syntax and binder
depth for its fixed root substitution/universe instance. The table is local to
one call; atomic roots do not allocate it. The same fixture allocates 10,200
bytes, and the 50-level version completes. Existing closure-cell, relocation,
snapshot and inspection tests pass; further controls compare with ordinary
substitution across shared binder contexts, arrays, fixpoints/cofixpoints and
separate calls. The lazy-substitution-chain fixture rises from 33,224 to 64,264
bytes from the additional local tables; this constant-factor cost is recorded,
not hidden. Full integrated performance remains to be measured after rebuilding.

## Integrated eta/substitution candidate

Worker `3a9480ea6f86050019bf78e3be3c0dc254ccb96b4cad361e99af1e862dc637dd`
and checker `7894f0aa99edad27476c4957952b666f4512dcdd54fa943d3015272825e28034`
rebuild successfully with the additional eta, saturation and substitution
repairs. Core plugins are rebuilt; the unchanged isolated importer remains
ABI-compatible. No replay or gate worker was active during rebuilding.

`final-gates-16` passes all nine runtime families, expanded private negative and
positive controls, dependency-digest tests, eleven native fixtures, twenty
legacy fixtures, a fresh small three-chunk import with sealed saves/reloads,
all 44 importer fixtures and 199 runner tests (two additional tests skipped).
Kernel, checker, fixture and local harness source hashes are pinned before and
after this gate. The new raw closure-substitution fixture measures 10,200 bytes
against the actual linked runtime, not only the separately compiled candidate.

Independent checking of all eleven native artifacts and their dependencies
passes in 1.78 s compatibility and 1.76 s strict, without `-admit` or `-norec`.
The large original-order Mathlib replay on this build is still required; the
successful `5fed2fe6...` replay above does not substitute for it.

The rebuilt checker also passes the direct four-flag policy unit and all eleven
CLI controls in `strict-checker-2`, including explicit UIP opt-in and rejection
of `-admit`/`-norec`. `full-eta-substitution` now replays from the original 21M
checkpoint with this worker and the unchanged isolated consumer importer.
After all gate/checker children exited, 21 completed test executables
(167,710,072 bytes) were removed; exact verified targets are recorded in
`cleanup-test-executables-6.json`. Sources, objects, records and proofs remain.
