# Integral-degree proof performance investigation

LATEST STATE: see the16:59 update at the end. Combined candidate integrated,
private suite and complete diagnostic proof passed; V9 fresh qualification
running. Older statuses below are a chronological investigation log.

2026-09-16: user asked for an algorithmic fix, not a longer validation timeout.
The v7 independent original-order segment did finish successfully in 2071.56s
(2049.39s inside the progress wrapper), but
`isIntegral_of_isIntegralElem_of_monic_of_natDegree_lt` alone took 1097.54s.
That theorem is absent from the Etale dependency slice. No kernel edits yet.

The owned `rocq-mathlib-etale-validation-v7-progress.service` was deliberately
stopped after stage 7 passed, while stage 8 was waiting for memory. Production
remains stopped. Stored progress files may still say waiting/running: no
continuation service is active. The sealed 30M prefix remains untouched.

`recheck.ml` runs the actual checker constant-check function on this one stored
proof, reusing the independently checked original-etale-v7 environment. This
is a diagnostic, NOT a fresh whole-library validation or production receipt.
The standalone executable statically links the current kernel. A candidate
must still pass full independent validation and regressions before promotion.

The initial `baseline-profile` exhausted its 240s diagnostic process allowance
while validating ancestor serialization, before reaching the proof. The harness
now uses normal checker Root/norec loading (still validates the root artifact,
reuses ancestor serialization). No kernel, production, or validation limit
was increased. Diagnostic RAM: 12GiB/no-swap plus 3GiB reserve; unrelated jobs
must remain untouched.

14:08 update: baseline-root and baseline-trace467 reproduce the slow proof.
The latter identifies one Algebra conversion (call467) exceeding 8 million
conversion steps, repeating Subalgebra/Subsemiring/Subring inheritance paths.
Both 240s diagnostic runs intentionally timed out before the whole proof;
the original independent checker remains the complete baseline success.

All experiments remain standalone: main kernel source/binaries UNCHANGED.
build-candidate.sh compiles a private Reviewed_conversion and Reviewed_typeops
into the copied checker. reviewed_mod_checking changes only the Typeops alias
and final typed conversion call; module/universe checking still uses native
Conversion types. This is NOT production evidence.

candidate-conversion.ml adds completed source-congruence caching to the lazy
projection helper. Existing private tests and the specific source_cache_test
pass (first test attempts had a fixture/API error, now fixed), but the real
proof still has millions of steps. Do not present this as the fix or promote.

suspended-conversion.ml instead starts from baseline and caches successful
comparisons of suspended syntax templates with their captured substitutions.
Immutable template identities/hash form keys; same local context/lifts/problem
and bounded read-only syntactic substitution comparison are required for hits.
No quotation or unfolding occurs in key construction. Focused negative tests
and full private test-witness suite PASS. Real partial replay suspended-v1 is
faster, but still unfinished; not yet a proven full speedup.

suspended2-conversion.ml shares the existing 32768-entry retention allowance
between physical and suspended cache entries instead of giving the new table
a separate allowance. Candidate tests/replay pending. No production timeout,
RAM cap, checking flag, theorem, or checkpoint has changed.

14:25 update: suspended-v2-full is still running under session11984, owned
timeout session1175716, diagnostic recheck PID1175766. It has reached conversion
662, CPU927s including ~53s loading. Main source/binaries still UNCHANGED; do not
promote this partial speedup. Memory holds ~4.8GiB. The revised candidate is
`suspended3-conversion.ml`, binary `checker.NvsKEBFn/recheck.exe`.

The remaining miss is reproducible: a captured substitution value has reduced
since the successful comparison, so fresh suspended syntax fails the old purely
syntactic comparison against its reduced value. The existing saved symbolic view
retains that original expression. V3 consults these views read-only, within the
same existing 1024-node lookup budget, only for the new cache's substitution
comparison. Ordinary fast_test behavior is unchanged (symbolic defaults false).
It also takes cache keys from the original saved view when available.

`suspended_symbolic_cache_test.ml` adds the reduced-capture regression and a
different-computed-argument rejection. The old V2 correctly fails the new cache
hit assertion (not a typing failure), in suspended-v2-symbolic-negative.log.
V3 passes it, including the rejection, in suspended-v3-symbolic-tests-2.log.
V3 also passes the full private test-candidate suite (suspended-v3-tests.log).
V2 extra tests pass universe substitutions and all local-context components.
Next: finish V2 full diagnostic; run V3 complete proof serially under the same
1800s/12GiB diagnostic limit. No production resume yet. Do not edit harness files
whose hashes are pinned by the active diagnostic.

14:30 update: V2 complete proof PASSED: 932.554 CPU seconds, process/result wall
1016.037s including loading and hashes, peak scope5,133,268KiB. This is still too
slow; it is not promoted. V3 was deliberately stopped with TERM to its owned
timeout1230667 after ~180s, not a theorem/type error (result255). It passed the
first large comparison but remained expensive.

V4 `suspended4-conversion.ml`, binary `checker.CZQYSzFl/recheck.exe`, now running
under session87155, timeout group1241728, in `suspended-v4-full` with unchanged
1800s/12GiB limits. Main kernel remains unchanged. V4 differs from V3 only by
checking saved original expressions BEFORE expanded values during symbolic
cache lookup. The old ordering consumed all1024 nodes on large reduced records
before considering their identical saved input expressions.

`symbolic_before_expansion_test.ml` constructs a well-typed1200-field value,
reduces two independent cells, and tests original-expression equality under the
same1024-node budget without mutating either. V3 fails this new cache-lookup
assertion (suspended-v3-wide-negative.log); V4 passes (suspended-v4-wide-tests.log).
V4 also passes full private suite (suspended-v4-tests.log) and extended captured
substitution tests (suspended-v4-symbolic-tests.log). No main patch applied yet.

Disk: ~13GiB free; the next validation artifacts are hundreds of MiB, and the
production disk admission is currently satisfied (30M checkpoint402MiB,
minimumfree5GiB). Do not delete any checkpoint or unrelated experiment.

## Current handoff, 2026-09-16 14:48 CEST

V4 COMPLETE PROOF PASSED: 844.594718 CPU seconds; total diagnostic process plus
loading/hashing918.184827s; peak guarded scope5,129,416KiB. Result is in
`suspended-v4-full/result.json`. Diagnostic sessions are finished.

Main kernel NOW CHANGED: V4 algorithm copied into
`_worktrees/rocq/compact-peano-view/kernel/conversion.ml`, plus a nonsemantic
refactor sharing cache eviction and combined-size diagnostic accounting.
No timeout/RAM/cache capacity was raised. The integrated private regression
suite PASSED (`integrated-private-tests.log`). The two new permanent private
regressions are `work/kernel-alignment-pass/suspended_conversion_test.ml` and
`symbolic_before_expansion_test.ml`, both included by test-witness-candidate.sh
and recorded in gates.py. Main worker/checker/plugins and a fresh ABI-only
importer have BUILT SUCCESSFULLY.

ACTIVE supervisor: `rocq-mathlib-integral-cache-v8.service`, running
`prepare-v8.py --attempt 2`. State/logs are in `prepare-v8-attempt-2/`.
Fresh importer: `work/kernel-alignment-pass/importer.Cg8NQIFf`.
Worker/checker hashes and pinned sources: `prepare-v8-attempt-2/candidate.json`.
It is currently checking the exact Etale target with the rebuilt worker.
After independent checking it invokes `../mathlib-etale-repro/finish-v8.py`,
which runs the complete existing 19-stage fresh qualification, then invokes
resume-v8.py only after all checks pass. The original-order independent checker
uses its ORIGINAL1800s whole-process limit (check.py), not the v7 progress timeout
workaround. Full validation may take hours. Max16GiB/no swap +3GiB reserve.
Unrelated Lean experiments must be preserved.

If successful, production resumes the unchanged sealed30M generation with
5M checkpoints under `rocq-mathlib-alignment-5m-etale-v8.service`; the supervisor
performs one startup observation and does not monitor production. Nested state:
`work/mathlib-etale-repro/finish-status-etale-v8.json`, later
`validation-etale-v8/progress.json`. On any proof/resource/check failure it stops
without changing limits or resuming. Do NOT claim full Mathlib has passed.

Preparation attempt1 failed before plugin compilation because the systemd PATH
lacked VSCode-bundled rg. Its logs are preserved in prepare-v8/. build-plugins.sh
now uses find as fallback when rg is unavailable; attempt2 rebuilt everything.
This was a launcher-environment failure, not a kernel/proof error.

V5 is an UNPROMOTED lambda-cache experiment. Its build and small tests passed,
but its large run never started: the single-heavyweight guard refused it with75
because V4 was running. No guard was bypassed. `run-eight.py` is only that
diagnostic's lower8GiB wrapper. Do not use V5 as production evidence; main code
and v8 qualification use V4 only. Do not edit pinned .ml/.py/.sh/.v inputs while
the active supervisor validates them; documentation updates are not pinned.

14:49 update: integrated Etale target compilation PASSED with current main
worker523eb3c32d0b1ff809022d6df6b26ae05fc754cefadc3e065255abb126e97e58.
Same import transaction: v7=220.157s, v8=68.092s. Full runner wall80.511s;
this is actual rebuilt worker evidence, not the private diagnostic executable.
Current checker hashab2892c24223e142048a985dd25c424a2bae13802bbde2dab0bd3340f8f9434b.
The supervisor is now on exact-independent, then full qualification. Preserve
this active service and all pinned sources unless a genuine failure needs work.

Latest: exact-independent PASSED in26.555s. Supervisor advanced to
qualification-and-resume; finish-status-etale-v8.json is now the live detailed
status. Full qualification remains pending; production has NOT yet resumed.

## 2026-09-16 16:14 CEST: stronger performance work, isolated candidate

User requests a robust algorithmic fix for the remaining multi-minute proofs.
V8 full Etale dependency compilation and independent checking PASSED; first
five validation stages passed. Original-order replay passed the integral-degree
theorem (Typeops895.267CPU seconds), reached the final Etale theorem31,651,932.

The exposed-lambda cache hole is now reproduced by `exposed_lambda_test.ml`:
WHNF a two-binder lambda, then `destFLambda` returns a fresh FLambda tail with
no symbolic FCLOS view. The current V4 cache cannot key it; V5/V6 can. This test
fails V4 at the missing-key assertion and passes V5/V6, including rejection of
different captured values, different contexts/lifts/problems. V6 is the main
V4 source plus the isolated V5 lambda-template extension (preserves integrated
shared accounting). Its exposed-lambda, captured-substitution tests and whole
private test-candidate suite pass. No integrated sources/binaries were changed.

V6 binary `checker.YgAPWMHL/recheck.exe`. Supervisor
`rocq-mathlib-lambda-probe.service` runs `probe-between-stages.py`: it SIGSTOPs
ONLY validation queue parent1389474 (identity checked), NOT its active worker.
It waits for original-etale-v8/result.json, then serially runs V6 diagnostic
`suspended-v6-full` with unchanged1800s/12GiB guard, and ALWAYS SIGCONTs the
parent on completion/failure. An independent65-minute fallback timer is
`rocq-mathlib-v8-queue-release.timer`. The main validation service remains alive.
No guard bypass or concurrent heavy proof check. Journal of lambda-probe is its
live coordinator status. Do not edit V6 source/binary/harness during its run.
If the coordinator is stopped, its finally handler releases validation. Inspect
the original queue state before making any new pause or restart decision.

V6 is NOT yet proven faster on the full proof and is NOT production evidence.
If useful, it still needs integration and fresh full qualification. Full Mathlib
acceptance remains unproven. Existing checkpoints and unrelated jobs untouched.

## 2026-09-16 16:32 CEST: DAG-aware structural probe

Original-order v8 PASSED: `../mathlib-etale-repro/original-etale-v8/result.json`
exit0, wall2601.932s. Final time included checkpoint serialization; it was not
a stuck theorem. The queue progress file is stale because its parent is held.
Production is still inactive. V6 full diagnostic is running (recheck1631277,
timeout1631230); it has reached conversion546 after ~400CPU seconds. No result
or claimed real-proof speedup yet.

V7 `suspended7-conversion.ml` extends V6 with an operation-local positive memo
for bounded, read-only syntactic comparison. Keys include physical syntax and
substitutions, or physical closures and equivalent lifts. Only completed
successes are stored. The memo never crosses probes/reduction/context changes.
Hits still consume the unchanged1024-visit budget; retention is bounded by it.
This follows Lean's sharing-aware structural equality idea without importing
transitive semantic caching into Rocq's mutable closure machine.

`syntax_dag_test.ml` fails V6's shortcut and passes V7: independent depth40 DAGs
compare in122 visits; unequal leaves/captures/lifts reject; wide inputs stay
bounded; expanded closure DAGs scale linearly;200 deterministic differential
tests against integrated conversion pass. Exposed-lambda and all private
regressions also pass. V7 binary `checker.bz3hhScv/recheck.exe` is pinned.
No main kernel source or binary was changed for these experiments.

IMPORTANT orchestration: the main `rocq-mathlib-integral-cache-v8.service` is
now also cgroup-FROZEN between stages, with no proof worker in its cgroup.
`rocq-mathlib-dag-probe.service` runs `probe-syntax-dag.py`, waiting for V6 success,
then serially runs V7 in `suspended-v7-full` (same1800s/12GiB+3GiB reserve).
Its finally handler THAWS the validation service. The first coordinator still
SIGCONTs queue1389474 after V6, but the freeze prevents an intervening stage.
Independent fallback timers: `rocq-mathlib-v8-queue-release.timer` sends SIGCONT
after65min from16:10; `rocq-mathlib-v8-queue-thaw.timer` thaws after70min from16:26.
If stopping coordinators, verify both the queue signal state and cgroup freezer
state. Do not strand validation or accidentally launch two heavyweight jobs.
V7 status: `syntax-dag-status.json`. Both candidates and harnesses are pinned;
do not edit them while diagnostics run. Further tests/docs may be added.

16:38 update: the V7 full-proof diagnostic was superseded BEFORE LAUNCH.
Its coordinator was stopped while waiting; the main validation service was
immediately refrozen (queue1389474 still SIGSTOPped by the first coordinator).
Active replacement: `rocq-mathlib-dag-alpha-probe.service`, script
`probe-syntax-dag-alpha.py`, state `syntax-dag-alpha-status.json`. It runs V8
binary `checker.7afZEMri/recheck.exe` / `suspended8-conversion.ml` after V6, with
the same limits, then thaws old validation. Existing fallback timers remain.

The public conversion entry point still did unbounded, non-memoized initial
alpha comparison BEFORE V7's closure probe. Independently allocated depth40
DAGs timeout5s on V7 via `default_conv` (not merely a helper). V8 adds a bounded,
sharing-aware initial alpha shortcut using exactly the existing head/universe
comparators, separate ordered CONV/CUMUL/nargs keys. Exhaustion delegates to
ordinary conversion. Public conversion regression now passes, as do288
differential comparisons with old eq/leq_constr_univs, DAG helper tests and
the complete private suite. No main source edits yet. V8 also corrects a V7
comment: Esubst.eq_lift IS structural here; there was no application-cache
hash/equality discrepancy. Omitting lifts from the new syntactic memo hash is
safe because equality still checks them, but is not a fix to the old hash.

16:52 update: V6 complete proof PASSED,767.758326CPU seconds (854.690569wall
including loading and hashes). V8 is running under timeout1684127, checker
1684170, currently near the final expensive comparisons. Its inner DAG memo
adds some overhead versus V6 on this particular proof; no dramatic full-proof
speedup has been established. Do not extrapolate the synthetic DAG improvement.

Additional V8 tests pass:200 randomized differential probe checks;288 alpha
comparisons with old eq/leq;32 independently allocated checked-body pairs,
including cases; public DAG comparisons through depth256; a valid1200-field
constructor that exceeds shortcut fuel still converts, while a changed final
field rejects. All three new tests are staged in kernel-alignment-pass, but
the live runner/gates and main source remain unchanged. New prepare-v9.py,
finish-v9.py and resume-v9.py are staged but NOT STARTED. Preparation requires
main conversion.ml bytes to equal suspended8-conversion.ml and a successful
complete diagnostic before building. Resume-v9 requires the three new runtime
test families, which must be added to gates.py only after old v8 is superseded.

16:59 update: V8 complete stored-proof diagnostic PASSED:812.774544CPU seconds,
893.582842wall seconds,5,137,428KiB peak. Candidate source SHA:
8e4ee1fb520162dac4981c4bd5a6a57c60440103b728720934f1875e1c45afe9.
Integrated source SHA (same source without its extra final blank line):
51ec5b54b77621dfc9e9d0cd4968d7bcc2046fb1b3a9320a068f082c51675aae.
Old v8 supervisor AND its owned heavy independent-check scope were explicitly
stopped. Stage7 original-independent was cancelled, not a proof failure; keep
its logs. Both fallback queue-release/thaw timers were stopped too. No old
supervisor is left frozen or signal-held, and production remains inactive.

The new candidate is integrated. Added exposed_lambda_test, syntax_dag_test
and syntax_dag_conversion_test to the permanent private runner and gate
families; adapted the suspended-template key test. Whole integrated private
suite PASSED (integrated-v9-private-tests.log); kernel git diff --check passed.
V9 preparation is now RUNNING under rocq-mathlib-integral-cache-v9.service.
It compares source bytes modulo trailing LF only and pins both candidate and
integrated source. DO NOT EDIT its pinned kernel/checker/test/script inputs.
Status: prepare-v9/status.json, then ../mathlib-etale-repro/finish-status-etale-v9.json
and ../mathlib-etale-repro/validation-etale-v9/progress.json. All19qualification
stages must pass before automatic production resumption from30,000,001.
Limits unchanged. Do not call this full Mathlib success or a dramatic proof
speedup. No recurring assistant monitoring of production after startup.

17:01 update: V9 build-core, build-plugins and ABI-only importer all PASSED.
Worker SHA a363c589e05023fecfe27114ef587aeeb88715717929eafedbd3dece21c00b36;
checker SHA914d4a35b2156c0e584837010cc519b6281d8847f2d33beec31f303a85db2a0b;
consumer kernel-alignment-pass/importer.KxXeEAdv. Exact Etale target PASSED
(80.627s complete runner,71.068s import transaction); independent checking
also PASSED, guard status0. Supervisor has entered qualification-and-resume;
full dependency slice is first, followed by the19stage batch. This remains
background validation, NOT a resumed production run yet. Production resume
is conditional on every fresh gate passing. Disk ~9GiB free, check_disk minimum
currently5GiB; no checkpoints, validation evidence or unrelated jobs removed.
