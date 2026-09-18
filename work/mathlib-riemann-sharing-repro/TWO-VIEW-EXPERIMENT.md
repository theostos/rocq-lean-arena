# Symbolic and reduced closure views — active experiment

2026-09-14. **Validated and production service started at 20:32 CEST. Do not
run either resume script again.**

Current runtime: worker e17936ee, checker 34488677. The complete gate in
final-gates-typeops-checked-serial passed, including 17 native/20 legacy/44
importer fixtures, 206 runner tests (two skips), private runtime tests, fresh
checkpoint/reload smoke, ordinary and strict native independent checks, and
11 strict-checker policy cases. All four Mathlib continuation artifacts passed
independent checking as recorded below.

Production service: `rocq-mathlib-alignment-5m-two-view.service`, from the sealed
25M checkpoint, five-million-line checkpoints, unchanged 1,800-second line
timer and 16 GiB cap. Validation receipt and runtime adapter are frozen in
`../mathlib-two-view-release-20260914`. Approval and certificate are
`two-view-resume-approval.json` and `two-view-consumer-certificate.json`.
The service must only be checked for startup; do not monitor the ongoing full
run on the user's behalf. Full Mathlib verification is not yet complete.

Startup handoff: preflight passed, MathlibTo25000000Reload started at 20:33:36
CEST and loaded the saved state successfully. The reload job is serializing
its state before the launcher advances to MathlibTo30000000. The service is
active; this is not a claim that the next five-million-line chunk has passed.
Progress: `../mathlib-alignment-5m-20260913-with-terminal/progress.json`.
Current attempt: `../mathlib-alignment-5m-20260913-with-terminal/attempts/20260914T183207870641Z`.

The one-time promoter's pgrep expression emitted a misleading long-name
warning when no worker was present. After launch its expression was shortened
to conservatively match `rocqworker.*`; this does not affect the frozen
runtime adapter or the running job. The actually executed promoter is preserved
as Git blob `039cff44ca64799ae76b0a6203d65e5ad649d1c4`, matching the receipt.

## Completed validation chronology

Current worker is e17936ee (two-view closures plus bounded application-domain
conversion reuse). Lie, SSet and derivative replays passed on that worker.
The continuous original-order replay from 25M passed all three Riemannian
targets with unchanged 120-second declaration limits and saved successfully
at 19:42. The broad worker gates also passed, but independent native checking
timed out in abbrev_congruence_order with the old b2ecc967 checker.
The cause was checker/mod_checking.ml using untyped conv_leq for the final
body-type check after both operands were already typechecked. The worker uses
typed default conversion at this point. Switching this one checker call to
default_conv_leq fixes the timeout; the same native recheck now passes.
The worker SHA remains unchanged; the new checker SHA is
`34488677886e8749696a3086edc2abbb5c9fb2da960881a682e7e01419305113`.
New private checker tests reject forged final types, reversed universe
inequalities and malformed bodies, and accept valid cumulative checks.
The first final-gates-typeops-checked attempt was rejected by the exclusive
resource guard when it overlapped a proof recheck (exit 75 from test-digests).
No guard or memory setting was weakened. Fresh gates now wait for the
independent proof rechecks and use final-gates-typeops-checked-serial.
Both must pass before
resume-two-view.py may run. Production remains stopped. No production
checkpoint was deleted and no commit was made. See TYPEOPS-CACHE.md for the
new cache's scope and safety conditions.

At 20:15 all independent Mathlib artifact checks completed successfully:
Lie 14.59s, SSet 0.90s, derivative 105.04s, continuous original-order segment
514.84s. The last record is riemannian-typeops-final/independent-original-order.json
(exit 0, range [25000001,25525775]). The serial regression service now starts
its fresh gate. Do not restart or overwrite completed proof rechecks.

## Chronological recovery notes (historical states, not current instructions)

### Resumed work at18:48

Production is still stopped. A detached, memory-guarded validation service,
`rocq-riemann-prefix-validation.service`, prepares `riemannian-original-prefix`
using worker7ce6e569 and the full sealed25M chain. run-traced.py now forwards
the owner-service name to the guard, which checks the actual enclosing cgroup.
No kernel build should replace the worker until that replay has finished its
post-run checksum validation.

A SOURCE-ONLY Typeops experiment adds a bounded successful application-domain
conversion cache to one typing-machine invocation. It keys the exact physical
environment and ordered immutable syntax pair; bounded structural comparison
is only a lookup optimization. HConstr inference caching is preserved. No
failure/exception is cached. Private tests in test-typeops-cache.sh pass for
context separation, directionality, failures, interrupts, syntax/DAG bounds and
retention. The worker has NOT yet been rebuilt with this experiment; no Mathlib
performance improvement is established. run-cache-traced.py enables only
observational counters for the first prepared-target replay.

At19:04 the prefix completed:849.19s total,
`RiemannianPrefixFrom25M.vo` SHA256
`0e186a5680cead618f7c467eb0bb62e88e32933e5dafcb13680d925cecb96fa8`.
The queued `rocq-typeops-candidate-validation.service` then built worker
`e17936ee0b3a7417d9452e083ccf9ef64cc1225eea856f2076a2456c6447bc3f`
and checker
`b2ecc96752fb7d3c86244fd4486c4837c95bddb15c825aba1f3572fdf2f3458f`.
`typeops-cache-native` passed0.49s, including negative domain/scope/sort
controls. The private test additionally invokes the real Typeops machine on a
well-formed beta-alias environment and checks rejection of an ill-typed second
application after a successful first one.206 runner tests(two skips) and17
consumer-adapter tests passed. The prepared Riemannian replay is pending under
the unchanged120s limit. This service has no production restart action.
Broad gates now include17 native fixtures and the private Typeops cache tests;
the old promotion draft still expects16 and must be updated only after actual
final validation. No production approval exists.

At19:12 the prepared replay passed all three reported targets under the
unchanged120-second declaration timers, then entered checkpoint packing.
Observational Typeops counters show substantial successful reuse (for example
8849 application comparisons with5277 cache hits in one61.3-second inference
call), but individual NormedSpace conversions can still take3–5seconds.
This is evidence of useful reuse, not a general complexity guarantee.
The checkpoint may change physical sharing, so a continuous original-order
replay remains essential. `rocq-typeops-final-validation.service` waits for the
prepared artifact's verified success, then runs Lie/SSet/derivative, continuous
25M→25,525,774, broad gates and independent checks sequentially. Its script
`validate-typeops-final.sh` NEVER restarts production. It stops on any failure.

The promotion draft now targets e17936ee/b2ecc967, final-gates-typeops,17 native
fixtures and the mandatory Typeops unit family. It still must NOT be invoked
until that final validation actually passes. Typeops source blob for recovery:
`51027d057b39aed9333984e7d2c4a57e26bc6d70`. No source changes to the importer or
to producer-pinned runner files have been made. No production receipt exists.

### State recovered at 18:20, before the Typeops experiment above

The then-current7ce6e569 worker survived on disk, but was NOT approved:
`riemannian-recursor-order/result.json` reports exit1,666.27s total. The
120-second declaration timer expired at25,505,940 while checking named
projections of Bundle.ContMDiffRiemannianMetric, after printing inner2.
Snapshots show Typeops.type_of_apply conversions and application-cache work,
not the previous quotation/lifting explosion. Peak cgroup RSS7415464KiB,
limit16777216KiB. Production remains stopped; no final broad gates or
certificates exist.

The same worker passed Lie57.16s, SSet10.20s and derivative155.38s. These
successes are not sufficient to promote it. No Typeops caching fix has been
implemented. Investigation found that Rocq ALREADY caches inference via
HConstr.Tbl inside execute; do not claim inference is entirely uncached.
One hypothesis to measure is repeated conversion across type_of_apply calls:
each default_conv call currently creates fresh conversion caches. Lean's
checker-local cache lifetime is longer. Context-sensitive immutable syntax
and positive-result-only reuse would need careful tests before changing this.

RiemannianPrefixFrom25M.v and RiemannianPreparedTargets.v were created to
prepare a reusable, proof-preserving original-order prefix ending immediately
before25,505,940. The prefix launcher was interrupted BEFORE creating
riemannian-original-prefix; there is no prefix artifact to reuse. All old
tool process-session identifiers died in the reboot. No worker is running.

Host diagnosis: boot-2 journal ends18:05:01, with VS Code extension host exit0
at18:02:09; boots followed at18:14 and18:17. No OOM kill was found in relevant
kernel/userspace logs. Sysstat at18:00 reports22941624KiB available; this does
not prove the cause of the subsequent host restart, but does not support
claiming an OOM. Current machine has about25GiB available.

New resume-two-view.py remains a BLOCKED draft requiring final validation.
It now plans an immutable receipt and frozen adapter under a fresh release
directory, avoiding perpetual checkpoint dependencies on mutable worktree
sources. No release directory or receipt has been created. Adapter tests17
pass (including runtime importer selection and restoration on failure).
gates.py now explicitly runs the runner/resource/checkpoint unittest suite,
records counts/skips and requires success. These new broad gates have not run.

All preceding kernel work is preserved. Pre-experiment CClosure blob:
`f485185999e74298661f06451071b31a415478fb`. Pre-experiment weighted conversion
blob: `e52326ba8d94edd73d0c225e2cf14bc3ea6ac26f` (rejected). Current conversion
uses bounded256/262144-step dependency attempts, followed by ordinary
conversion; it no longer forces global non-sharing. This is a Rocq adaptation,
not Lean's exact search algorithm, and still requires broad validation.

## Rejected experiments

- Non-sharing WHNF memo, worker e963...: SSet120 timeout, including the ordinary
  non-sharing control. It conservatively invalidated on all closure mutations.
- Selective symbolic no-update + memo, worker7e327...: Lie passed64.29s with
  sharing enabled, but SSet timed out both normally and with ordinary unfolding.
  CClosure Git blob `e02ad033cf4fcbe66eef00f11b38894391f64696`.
- The same with one-time FCLOS-to-FApp materialization, worker379b...: SSet
  ordinary control still timed out. Blob `dd6bdabf4536c40749e7279584bd3d19f902a5b3`.
  `sset-plain-materialized` accidentally started after a build warning/error,
  ran the OLD worker, and was agent-terminated. INVALID.md records that fact.
  `sset-plain-materialized-built` is the actual failed candidate replay.

Those implementations were removed via apply_patch against the exact saved
pre-experiment CClosure blob, not by resetting the user's worktree. Their mock
memo test remains archived in whnf_memo_test.ml, no longer invoked by the suite.

## Two-view design under test

Keep ordinary destructive reduction sharing. Before overwriting a conversion
cell, optionally retain a separate symbolic view. Cheap beta/iota/zeta
comparison reads the symbolic view; full reduction uses the cached reduced
cell. A symbolic-copy spine is instantiated once and is not overwritten by
later update frames. There is no global term cache or mutation-generation
counter. Closure metadata dies with the conversion heaps.

The first version captured only outside cheap reduction (worker16b561...,
blob83de63476bc948489666670c693f1ac23b233ceb). Ordinary SSet passed10.17s:
`sset-plain-two-view/result.json`. Lie timed out at120s:
`../mathlib-lie-trace-repro/proof-two-view/result.json`.

Update frames can survive cheap reduction and overwrite a cell during later
explicit delta unfolding. Therefore capture must precede those frames too.
The earlier-capture version (worker2ffca...) exposed a constructor-shape
invariant violation in Lie, not a timeout. A naive lift wrapper around a
reduced constructor is invalid at reducer call sites expecting constructors.
The current code lifts both views while retaining the reduced head shape and
per-operation constructor-DAG sharing; resubstitution drops stale metadata.

Focused tests: symbolic_views_test.ml is invoked by test-closure-candidate.sh.
It covers both visit orders, stable full and symbolic reuse, disabled/nonsharing
scopes, open symbolic arguments hidden by a closed reduced result, and lifted
constructor DAGs with retained views. The open-argument test failed before the
lift correction. The earlier memo/portfolio test invocations are not applicable
to this design; their historical source files are retained.

The shape-preserving version (worker c1738c...) passed Lie in63.05s but ordinary
SSet timed out at120s. Adding failed-congruence caching (3fb3c7...) and then
successful application-process caching (6b9cfe...) each still timed out in SSet.
Those caches had hits; cache hits alone are not evidence of a performance fix.

The selective same-head symbolic congruence version (worker05380e...) failed
Lie at120s. Its two difficult inheritance paths have different outer heads,
so the same-head-only check cannot repair that comparison by itself.

The current experiment uses bounded symbolic recovery inside a conversion,
with ordinary shared conversion as fallback. It counts conversion steps, NOT
wall time or all reduction work. Failure hints suppress only this optimization,
never certify inequality. Both opposing replays are still required.

Worker `8a1cb6e03e35b2a1cfb22557bcabab3acc7d033acc63889a3f8c366f7dbf5ae6`
passes BOTH normal-policy proof-preserving replays: Lie64.58s
(`../mathlib-lie-trace-repro/proof-symbolic-recovery`) and SSet30.18s
(`sset-symbolic-recovery`), unchanged120s theorem limits. But
`derivative-symbolic-recovery` hits its180s theorem limit (190.42s total).
It is therefore still NOT approved. `derivative-plain-symbolic-recovery`
is the one-setting ordinary-unfolding control, not a production success.

Consumer `importer.y7jxl7hG`, plugin SHA256
`cb534f32f051b351405a10fd69c009b0b97dadf8cecea413634976516e3c3a02`,
matches the new interface and preserves the exact producer `lean.ml` source
SHA256 `665383b4f65435ede188cc237eb3a07dc92700e3fe0917d7cd0efe60d622c7d2`.
Closure, witness and cache tests pass, including negative type-witness checks
and both explicit symbolic/ordinary reduction modes. Broad gates are pending.

Further derivative controls:

- `derivative-plain-symbolic-recovery` (8a1cb6...) also timed out180s.
- `derivative-deferred-unit` (7e341a...) avoided unconditional early full unit
  type reconstruction on projected flex/flex comparisons but still timed out.
  Full unit checks remain when neither side unfolds; negative witnesses pass.
- `derivative-process-cache` (2d738a..., trace-call503) also timed out. The cache
  now keys complete bounded argument processes rather than retaining8/32
  variants per constant-head pair. Cycling128 variants and mutating a closure
  after key insertion are covered by the private cache tests.
- `derivative-abbrev-first` (fef358...) also timed out. It fixes a real hint
  mismatch but is not sufficient: the same-head argument shortcut now respects
  Expand for transparent definitions. `DerivativeHints.v` confirms the loaded
  Nat_recOn is Expand; the export explicitly contains `#ABBREV` for it. A native
  abbreviation/opacity/negative fixture was added, not yet run.
- `derivative-plain-shared-budget` (2a62fb...) PASSES110.31s total with the same
  180s theorem limit. Recovery now shares16384 conversion steps per top-level
  conversion, in addition to its4096 per-attempt allowance. This prevents the
  recovery overhead from multiplying without bound over fresh argument pairs.
  These are conversion-step limits, NOT wall-time bounds.

One candidate therefore removed the unbounded dependency-first second
attempt. After the existing256-step fast attempt it used ordinary conversion.
Global non-sharing and the unused `conversion_retry_environment` helper are
gone; its private test is archived, no longer invoked. Lie timed out in both
`proof-ordinary-recovery` (ae6cc2...,131.68s total) and
`proof-typed-ordinary-recovery` (bcb455...,133.65s), the latter enabling
constructor proof-field masking. The queued SSet/derivative tests did not run.

A bounded65536-step dependency attempt before ordinary fallback also timed
out (`proof-bounded-dependency-recovery`,df9d66...,132.84s). Sharing the whole
strategy allowance with recovery instead of clipping recovery to16384 did not
fix it (`proof-shared-strategy-budget`,8ca4fb...,131.43s). Its call924 trace
exhausts the strategy allowance, then enters the same slow ordinary path.
These limits count conversion steps, not all reducer work or elapsed time.

The current build adds a physical-identity shortcut with equal relocations in
`fast_test_under`. A focused30-level shared-DAG test failed before and passes
after the guard. The test also rejects equal cells under different relocations.
An initial extra positive test incorrectly used environment keys as local
variables; it was corrected to use bound FRel closures. All private witness/
cache tests then passed. The `*-physical-fast` sequence runs Lie, SSet, and
derivative independently, even if an earlier case fails. It is still in flight.
The physical-fast build8b2d05... passed SSet10.17s and derivative115.35s but
failed Lie131.34s total (120s theorem timeout).

## Superseded candidate: all three isolated cases pass, original order fails

Worker **9d907de6f4d76524dd416a0dbc2b08a66c5001928aa51a0ea55ffe7232c7956b**
uses262144 steps for the constructor-masked dependency attempt. No theorem
timeout or checking flag changed. Results on this SAME build:

| Replay | Total wall seconds | Artifact SHA256 |
| --- | ---: | --- |
| `../mathlib-lie-trace-repro/proof-bounded-262k` | 57.3369 | `4ec91b145cda5d5698fd4c77444c311801842245fa910a78997c72875e95e1b5` |
| `sset-bounded-262k` | 10.1774 | `aebecd62cd1186b80813f115893c93dbd60ccd116d2ac3814559a2f323b77b5f` |
| `derivative-bounded-262k` | 130.3209 | `4ea94416587706c5a08479a3aa8dadd4f499a7c8df18ff430ea50da32eae90b3` |

These timings include loading/saving; the unchanged theorem limits are120s,
120s,180s respectively. Lie uses trace-call924 for observational logging, not
an alternate conversion policy. All dependency proofs are retained.
Conversion Git blob: `46db9c3046570f9ac62933695e3828e8d8dd7b04`.
Private witness/cache tests pass, including whole-strategy/symbolic exception
propagation without poisoning failed-congruence caches.

`riemannian-bounded-262k` FAILED at25068632 (Witt-vector auxiliary proof),
before the Riemannian targets, with an unreduced FLambda anomaly. Total worker
wall169.50s, peak5.67GiB. No production restart was approved.

## Neutral-view invariant repair (in validation)

`whd_stack` previously used the cell's Ntrl mark to skip `knr`. That mark only
certifies the reduced view: restoring a symbolic view can reveal a beta-redex.
A small test reproduced the missing reduction; the new version uses the full
head machine in symbolic-core mode even for Ntrl cells. The regression includes
a term checked by Typeops before reduction and passes after the correction.
The lambda anomaly check was retained, with more precise stack diagnostics.

Worker9c951ff8778aea4bc80a3f9b7dd2d9c1dad2c69da0b6b1cf63cee49b5097a1c7,
checker56be18f48518b2ee44ef932cfb85d862ffbfaaf0c04f3e5ea7d2230edc499b40.
CClosure blobc26df877e7742233e33d5556f11e13e927244619;
conversion blob71e852bf735292c81aba3087edfa1afaa50677b2.
`riemannian-neutral-recovery` passed25068632 and reached25097703 at17:31;
it is still running, followed by fresh Lie/SSet/derivative replays.

The new native abbreviation fixture initially timed out5s. A control forcing
nat_rect to Expand passed, but is NOT validation: the importer only explicitly
expands primitive-record recursors, not all generated eliminators. The fixture
has been restored to regular nat_rect priority. A bounded read-only
`constructor_fixpoint_application` helper has now been added to source to
prefer unfolding a transparent lambda/fix wrapper when its actual structural
argument is already a constructor. This mirrors the relevant demanded
primitive-recursion step in Lean; it is not a global recursor classification.
The helper does not certify equality and does not override opacity. It is
not yet in the running9c951 worker. Its private witness build passed;
the unforced native fixture and all final performance gates remain required.

## Current candidate (17:43)

Worker `7ce6e569024b1756c9576773b77fca5a21d91ce919a189bd363e29b90e62fcad`,
checker `2563ad5ec232eee2be339673901a6d3fee2c6e64f93d7aa69126d7736af6148d`,
conversion blob `6ce5c9d0698edcb3aba3ffa8b60ed0b472d1de96`.
Includes the bounded constructor/fixpoint observation above. The restored,
unforced native abbreviation fixture passes0.59s, now also testing regular
parameterized recursors, successor constructors, neutral negative cases and
partial applications. `abbrev-imported-recursor` remains CONTROL ONLY.

`proof-recursor-order` passes57.16s; `sset-recursor-order` passes10.20s.
Derivative and original-order continuation are still pending on this build.

The old9c951 `riemannian-neutral-recovery` was agent-stopped during checkpoint
encoding after reaching25,505,939. Its INTERRUPTED.md records the reason; it
does not certify the three Riemannian targets. The new
`RiemannianWholeFrom25M.v` imports25,000,001 through25,525,774 in ONE original-
order command, with120s per declaration (including all gaps). This avoids
serializing the full environment six times and is a stricter timeout gate.
The production1800s per-line policy has not changed.

`resume-two-view.py` is a new fail-closed promotion script for this exact worker
and checker. It requires completed full gates, strict native checking, checker
policy tests, independent target checks and the continuous original-order
replay before creating the ABI-consumer certificate. It has NOT been run.
The historical `resume.py` remains rejected and must not be used.

`run-traced.py` now hashes each unique export only once in its initial source
inventory (the six continuation commands name the same5.3GiB file). The full
producer-seal checks and post-run checks are unchanged. Consequently earlier
invocations that pin the old wrapper cannot be reused as final approval.

The new `../kernel-alignment-pass/consumer_toolchain.py` provides an explicit
hash-pinned ABI-only consumer profile, without modifying producer manifests or
ignoring old checkpoint inputs. Its15 fail-closed tests pass and the real
producer/consumer source inventories match exactly. No production certificate
has been created or used. The adapter is included in the broad gate's source
pins and tests, and requires a separately approved validation manifest.

`RiemannianFrom25M.v` prepares an exact original-order NDJSON continuation from
the sealed25M chain through the three reported Riemannian targets, with120s
limits on those targets and1800s on intervening declarations. `run-traced.py`
now has an explicit checkpoint-limit option to verify/pin the entire25M chain.
This avoids regenerating a3M dependency-only prefix; it is not a recheck of the
first25M proofs by the new worker, and its producer seals remain unchanged.

This experiment now changes the public CClosure interface. The original pinned
producer importer `importer.lFy9zJVL` is unchanged. Consumer `importer.pmbc8lbm`
was rebuilt from those exact importer sources for the previous interface; the
new `infos_with_symbolic_views` interface is supported by the isolated consumer
`importer.y7jxl7hG` recorded above.
Existing generation seals and producer profiles must not be edited to conceal
that ABI change. No production resume is approved.

Build/replays remain sequential under the guard; tiny private unit executables
have a separate1GiB virtual-memory limit.

Still required: opposing Lie and SSet with ONE normal production policy,
derivative and combined Riemannian proof-preserving replays, full regression
gate, strict native independent checks, target continuation checks and then
artifact-pinned25M continuation. A diagnostic SSet success is not approval.
