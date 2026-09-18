# Char successor crash investigation (15 September 2026)

Current candidate (18:11 CEST): v13 qualification is running after v12 failed
the direct-dependency legacy fixture. Recovery entry
point: `DECLARED-ORDER-CONTINUATION.md`, `validation-v13/progress.json`, and
`finish-status.json`. Sources/binaries are pinned; do not edit during the run.

Latest status (15 September, 17:52 CEST): both v10 and v11 timed out on the
Riemannian original-order regression at 25,505,940. The supervisor stopped
without launching production. See `TYPE-QUERY-CONTINUATION.md` for current
candidate details, evidence, and the separate observational diagnostic service.
The status paragraphs below are chronological history, not current status.

Current status (15 September, resource-budget continuation): the detached
`rocq-mathlib-char-succ-validation.service` is active. Batch `validation-v10`
passed the native alias fixture and started the previous-Char replay under an
enforced8GiB/no-swap cap. Check `validation-v10/progress.json` and
`finish-status.json` before resuming work. No production restart yet.
Large replays wait for19GiB available (16GiB cap plus3GiB reserve), within the
user's20GiB allowance. Unrelated Lean experiments remain running. Seventeen
scheduler/supervisor tests pass; verified pre-launch memory refusals are
archived and requeued, but started compiler failures stop validation.
The previous resource-only refusal is retained in `validation-v9` and
`finish-status-v9.json`. Earlier sections below are chronological history.

- Production generation: `../mathlib-alignment-5m-20260913-with-terminal`,
  failed attempt `20260914T223351757378Z`, sealed cursor 30,000,001.
- Crashed worker SHA256:
  `80c4781a4738d0509f88630d70583415a93b8d88a1f15306561fd88c70e70940`.
  Baseline binaries are preserved in this directory.
- Before-this-investigation `conversion.ml` Git blob:
  `8d24343966f1dc90620d57d4598e72437221e514`.
- The production guard reports status 255 and peak 13,572,776 KiB, below its
  16 GiB ceiling. This does not establish an OOM kill. The repeated conversion
  frames and SIGSEGV are consistent with excessive native recursion, but the
  responsible conversion pair still needs to be identified.
- Merely sampling `getenv("ROCQ_EXPERIMENTAL_DEEP_FAST_TEST")` does not mean
  this experimental switch was enabled. No such switch is being enabled here.

## Reproduction coverage

`slice.json` pins a proof-preserving combined slice: 232,076 selected NDJSON
records, zero abstractions, including both the new successor proof and the
previous ordinal proof, through the enclosing `Char.ofOrdinal_le_of_le`.

The extracted successor target **passes on the crashed worker**:
`baseline/result.json`, 10.17 s including loading and saving; declaration
checking itself is about one CPU second. Therefore this slice is not yet a
reproducer of the production failure, and a slice-only success cannot validate
a correction to it.

`CharOriginalPrefix.v` reconstructs 30,000,001–30,778,864 from the sealed 30M
checkpoint. `CharOriginalTarget.v` isolates the next record under a 20-second
declaration bound. `run-original.py` supports bounded scalar conversion traces.
`CharOriginalWhole.v` is the required uninterrupted original-order validation
through line 30,806,240, covering both reported failures and the enclosing
ordinal theorem. `check-original.py` independently checks that new module;
it explicitly reuses, rather than rechecks, the first 30M dependency proofs.

## Hypothesis to test (not a finding)

The previous change gave constructor-driven eliminators priority over other
delta unfolding, but its recognizer also accepts arbitrary recursive Fix
definitions. The pinned Lean 4.29 kernel distinguishes primitive recursors
from ordinary lazy-delta definitions and has literal arithmetic reduction.
Check whether this broad priority eagerly expands arithmetic in this context.
Do not simply revert the prior Case/local-alias support: the old ordinal
failure must remain covered.

Reference: Lean commit `98dc76e3c0a9b856c9b98726b713fb04fab16740`,
`src/kernel/type_checker.cpp` (`whnf_core`, `reduce_recursor`, `reduce_nat`,
`lazy_delta_reduction_step`, `is_def_eq_core`). Local exact reference is in
`../mathlib-riemann-sharing-repro/lean-4.29-reference/`.

## Further evidence

- `original-prefix` passes on the baseline worker, including the save, in
  1,149.94 s (guard peak 10,107,744 KiB); artifact SHA256
  `bfc8edd2256ed9dd5617f836671d5bd9dc42c8e5f349ddf9fface3608ef11a8c`.
- `original-baseline` also passes after reloading that immediate prefix:
  146.71 s including loading, with a debugger stop after successful import
  checking and before saving. This diagnostic produced no certified artifact.
  Therefore even that reload does not reproduce the production failure.
- `FixPriority.v` does reproduce an independent scheduling defect on the same
  baseline worker: `costly 26 = wrapper 26` times out in 5 seconds. Prioritizing
  the arbitrary recursive call over its simple alias forces needless evaluation.
- The unbuilt candidate restricts the *new cross-definition priority* to Case
  bodies, retaining existing same-head Fix support and the previous Case/local
  alias improvements. It does not add an equality rule or change the importer.
- `production-order-baseline` replays uninterrupted from 30M under the exact
  production module name `MathlibTo35000000`, through both Char targets. It is
  still running on the old binary, with a 120-second declaration bound.
- `check-only.py`/`.gdb` are diagnostic-only: the breakpoint is at the first
  checkpoint pack, which is reached only after `do_input` finishes all requested
  declarations. Such a result is not a .vo or production checkpoint. Final
  acceptance uses saved original-order replay and independent checking.
- `validate.py` and `resume.py` are prepared, not executed. Promotion requires
  all 18 stages on the same pinned worker/checker and unchanged producer seals.

## Reproduction confirmed and candidate built

`production-order-baseline` reproduced the failure at 30,778,865 under the
production module name: the 120-second per-declaration timeout fired. Total
diagnostic time 824.36 s; peak 13,136,716 KiB. Conversion 105723 (dependency
preference on) ran for ten CPU seconds; fallback 105724 (preference off) then
grew into the repeated conversion stack. The completed diagnostic has no .vo.

The small alias trace also shows the costly side being expanded at the first
comparison of `costly 26` against `wrapper 26`, then timing out inside recursive
reduction. Baseline evidence is retained in `fix-priority-trace/`.

Build succeeded on 15 September at approximately 09:52 CEST:

- worker SHA256 `1d6c0c784ddd312bec0de4fb1b83c644feeb85f0139b9f15389f1e36415e7f66`
- checker SHA256 `937db5fa292849ce3f75c058389160157c849482dfe11cbe6bcf9c43ec3fc14a`

The first validation stage FAILED: the recursive alias test timed out. No
promotion or production restart occurred. The candidate trace shows the alias
now unfolding correctly, but the next same-head comparison still skips even
identical arguments and evaluates the recursive function. Evidence is retained
in `validation/`, `final-alias/`, and `fix-priority-candidate-trace/`.

The second candidate adds a bounded read-only argument-reflexivity probe to
that unfolding preference. It accounts for suffix shifts, does not concatenate
arrays or quote closures, and leaves all equality checks to ordinary conversion.
Unit controls cover split argument frames, shifts, changes, update frames,
unsupported eliminations, and budget exhaustion. Not yet built or validated.

Candidate 2 (worker `94c5db8f869ac0e192ba3452b1df4370c414d87b8559dfec3b48b22df88dc51a`)
passed the native alias and private tests, but FAILED the previous ordinal
target at its 120-second declaration limit (`validation-v2/`). Restricting the
cross-head preference to Case is therefore rejected. Candidate 3 restores Fix
and Case preference, retaining argument reflexivity and adding a bounded
direct-head-alias exception. This is still a candidate, not a validated fix.

Candidate 3 exposed the alias correctly but still failed the native test. A
scalar trace (`alias-views/`) identified FConstruct on one side and suspended
FCLOS(App(Construct,...)) on the other. Candidate 4's scheduling-only constructor
bridge passes the full native fixture (both alias directions, discarded branches,
negative/opaque cases) in 0.55 seconds and the previous Char target in 20.16
seconds (`succ-candidate4` under the ordinal reproduction directory).

The next version handles mixed forms beneath constructor/application/shift
wrappers too, retains the existing equality rules, and bounds lambda-list
reconstruction before allocating it in the pre-existing fast test. New private
tests cover nested mixed views, substitutions, shifts, arities and distinct
constructors. Temporary argument-view tracing has been removed. The original
uninterrupted production failure is not yet validated on this version.

Candidate 5 validation is running in `validation-v5/` (session 23141 at start).
Worker SHA256: `718ec597610099899b4c6f1acc2080017001263412f7e14a6980f82eb2a23ba6`.
Checker SHA256: `4d91734bcb44e488a90c4345ee27427cc6169ed749ee9b8dde539b625958a63f`.
The full native fixture and private tests passed before starting the batch;
the batch's alias and previous ordinal stages passed too. All code/script/V
inputs are pinned for the batch: do not edit or rebuild until it exits.
`resume.py` reads `validation-v5/passed.json`; it has NOT been invoked. Full
Mathlib remains paused at the sealed 30M checkpoint.

Candidate 5 batch STOPPED at combined-char: the fresh combined slice now
reproduces the successor failure at exported line226680/original30778865,
120-second declaration timeout, peak7428844KiB. The earlier target-only
replays after loading a saved prefix were insufficient. No restart/promotion.
The current candidate preserves the old ordinal and native controls, but is
NOT a fix for the actual successor failure. `whole-entries-v5` is collecting
conversion entry IDs for that smaller fresh reproducer (session11159).

Fresh trace `whole-trace-22420-v5` identifies Nat_Linear_Expr_recl as the stuck
left head at step20. Its opposite is unfolded through UInt32/BitVec/Nat.mod;
the bounded strategy exhausts262144 steps, dominated by PProd constructors,
then the unbounded fallback stalls. No successful production repair yet.

IMPORTANT CURRENT DIAGNOSTIC BUILD: conversion.ml temporarily prints the
step20 recursor body/strategy/major-argument views and intentionally raises
"Diagnostic stop after observing eliminator major argument" when conversion
tracing is enabled for that call. This block MUST be removed before final
validation. It is not a production candidate. All earlier validations stopped.

Diagnostic completed (`whole-major-view`): the expression recursor is eligible
by declaration shape/strategy (transparent, 6 outer parameters, Fix major0),
but actual argument6 is FProj, invisible to the old cheap recognizer.
The temporary diagnostic/error block HAS NOW BEEN REMOVED. Candidate6 adds
`projected_constructor_major`: gate on a projection head, isolated snapshot
with 1024 shared copy/reduction steps, fresh reduction table, retained
transparency. Only its constructor result guides unfolding; no equality rule
changes. Native tests now include projected majors for Fix and Case and an
opaque-source negative control. Build and fresh replay remain to be done.

2026-09-15 continuation: Candidate6's boolean observation was insufficient.
Native tracing confirmed projected-major inspection succeeded, but the original
major survived wrapper unfolding, leaving its source below Zproj/Zfix; stack
congruence then compared discarded branches. Candidate7 publishes the actually
reduced constructor from the isolated snapshot into a copied argument frame.
Both local approximation pairs are rebound. Worker 7eaea9a41e7d360af1f504829e0ae14c5c45cf691ad81a03039210d056ac89ea.
Native fixture passed in 0.57s (native-candidate7-checked). The original negative
control using Opaque on a Definition was invalid: baseline80c also accepts it
at Qed (opacity-baseline). Replaced by a genuine Qed-bodied opaque constant.
Additional both-head/open-field/lift controls have been added, not run yet.

whole-candidate7 fresh replay: first costly conversion now succeeds, but later
call22459 exhausts its bounded strategy, then22460 stalls until120s declaration
timeout on the same successor proof. Peak7467968KiB, not OOM. Production NOT
resumed; no full validation passed. whole-candidate7-trace now traces22459.
Other user's /tmp/beq-research Lean REPL jobs consume about13GiB; do not kill.
Native helper uses enforced1GiB, fresh Char slice uses enforced8GiB with normal
3GiB reserve. No production resource policy changed. Asked user to free those
jobs when convenient; original-order replay requires the normal16GiB allowance.
Temporary native diagnostic printing was removed before candidate7 build.

Candidate8 broadened demanded-major reduction beyond projections (Bool_recl's
major is Int.beq', comparing coefficients against0/1). Native expanded fixture
passed0.55s. Its new LocalDef ascription fixture initially elaborated expensive
26/27 before Qed; stopped that diagnostic and used1/2 for the binding test,
keeping26/27 in the distinct performance fixtures. 29 new private tests in
ALIGN/projected_major_test.ml passed (whole lightweight harness13.16s).

Candidate8 regressed the fresh prefix: at slice148807
Lean.Grind.CommRing.Mon.revlex_k_eq_revlex, conversion14136 enters an endless
congruence pattern Nat_recl -> Mon_recl -> Bool_recl -> Ordering_then'.
whole-candidate8-early-trace records it. Both diagnostic replays used a stricter
30-second per-declaration limit, same CharWhole module name and complete input.
No acceptance evidence. Possible lost shared/symbolic arguments during eager
major publication; still investigating.

Candidate9 first preserves direct aliases and same-head syntactically identical
original arguments before publication. Worker e299ef8e732fd88c3de6d9d900bac930d8ecc05e9cbc774d6f6c9b609e505c3c,
checker8189a1845f5b05397d544342017eef4847f4cba20af68d8b52ed5cc150120174.
Native expanded fixture PASS0.68s. whole-candidate9 running with30s perdecl,
entries andtrace14136 (session10482). No heavyvalidation/restart yet.
User confirmed unrelatedLeanREPLjobs closed; normal16GiB replay memory now fits.

2026-09-15 after another VSCode interruption: old subagent IDs no longer exist.
Candidate9 passed the successor proof and Char.succ? in the fresh combined
slice, but old ordinal conversion24051 still timed out (30s/declaration).
whole-candidate9-ordinal-trace shows Bool_recl's computed major stuck while
the opposite Int arithmetic unfolds. Candidate10 added inspection-only
FPeanoNat constructor exposure: precharge the binary borrow prefix, then use
ordinary constructor reduction, never unrestricted compact arithmetic. Native
passed0.56s, but fresh whole-candidate10 still timed out on the old ordinal.
Its wrapper was interrupted, so the run.log records failure but no result.json.

Diagnostic whole-major-copy-diagnostic confirmed the selected major is
Int_beq' and snapshot copying completes; reduction is what exhausts the1024
budget. whole-major-budget-diagnostic showed both operands are projected
closures and this exact condition completes with4096 (also16384) shared
copy/reduction steps. Those diagnostics did NOT publish their results; failed
replays are diagnostic evidence only. All temporary observation printing was
removed before candidate11 build.

Candidate11: demanded-major budget4096, same unchanged30s/declaration test.
Worker b09a838e240aa144117fad6f82fa74c76076a78a39d748c0dee3c1b4a726a85e,
checker52181bd6b6db355b566caf5c4958242c8cc040253938302037d4405522d02d17.
whole-candidate11 running(session97836); private witness suite(session43299).
New ALIGN/peano_inspection_test.ml passed in the private closure harness:
checked Nat/double, small ordinary-reduction agreement, a200000-bit untouched
suffix, oversized borrow-prefix refusal/allocation bounds and non-mutation.
Its source and test-closure-candidate.sh are the only new test edits in this
resumed turn; projected_major_test.ml oversized substitution now5500 entries
to remain over the new4096 bound. No full validation or production restart yet.

Candidate11 completed: whole-candidate11 PASS105.23s with all232076 records,
no abstractions, and both Char regressions. Witness suite29/29 passed.
User correctly objected that choosing4096 is not a principled solution;
candidate11 was NOT promoted and no final validation/production restart ran.

Lean pinned type_checker.cpp confirms demanded recursor-major WHNF, preserving
the original immutable expression on a stuck major. Prototype demanded-v1
replaced bounded snapshots by ordinary shared WHNF and removed the temporary
inspection-only compact Peano code/test. Native fixture PASS0.86s, but fresh
replay regressed slice210820 Int.Linear.eq_of_core (30s declaration timeout).
Demanded-v2 added constant proof-irrelevance guard and removed arbitrary
size/depth bounds on the demanded path. Private29/29 PASS, same early replay
regression (whole-demanded-v2, trace21221/21222). Not an OOM (~600MiB).
Trace repeatedly compares open Poly_recl/Bool_recl bodies below a neutral Rel4.

Now testing non-destructive ordinary reduction (existing non-sharing machine
mode, no snapshot-copy budget) for the demanded-major query. Hypothesis:
shared closure updates from a failed major reduction lose useful symbolic
representations; Lean retains the original expression in this case. This is
not yet established. Production remains stopped at the sealed30M checkpoint.

Non-sharing experiment: first launches stopped at plugin ABI mismatch (not
proof failures); rebuilt core plugins and staged an identical-source consumer
importer.kpPrho35. Native native-demanded-nonsharing-abi PASS0.54s.
whole-demanded-nonsharing-abi PASS105.23s, both Char regressions and the prefix.
Worker00e0b7a9a8f9f680021b3a3afa9eae3a172a40759ca3af94c895a813fbeffa34,
vo95e5c10372084c5ad8a73cb8e0ed66185322ee5acd77e24add629e62caee0dde.
Private31/31 including source-root preservation passed. This is strong evidence
that mutation of original major cells caused the demanded-v1/v2 regression.

Added a shared let-DAG regression: depth8/16 allocation243472/62390032 bytes.
Non-sharing FAILED31/32: preserving syntax alone duplicates computation.
Current implementation under build uses a private call-by-need view: an
on-demand original-cell -> owned-cell map consulted by knh, normal sharing
updates only on those owned cells. No whole-environment copy, demand-step
cutoff, or new equality rule. It is not yet tested. API change requires core
plugin and identical-source importer rebuild before fresh proof replay.

Private call-by-need candidate completed: worker
befbefc96a53a9176abbe8acfa35f7318fa8cdaa88e6c8c9cdb6475171fe8e16,
checkerc2121a28ac1275bb61e5c45f2db27a4f0d3f197c77f24cca7a3e902c9803212f.
Core plugins rebuilt; identical-source importer.k9WSHRtn staged.
Private32/32 PASS, shared let-DAG allocations10048/18880 bytes(depth8/16).
Full existing closure suite PASS. Native-demanded-private PASS0.56s.
Whole-demanded-private PASS100.22s (no abstractions,30s/declaration),
vo9d9301443f80195d1205c2ca0bbb316ab71d72b2e3e1939450b25a0520be183d.
Independent check of all new CharWhole declarations PASS19.81s; foundation and
stdlib reused explicitly (-norec), not a full independent Mathlib check.

Prepared finish.py for detached full validation then conditional resume;
six mocked control-flow tests pass. validate.py/resume.py now use the new
ABI-only importer and explicitly require the private-demand test family.
Two new unrelated Lean REPL processes (1613445/1642332) use~13GiB combined;
asked user to finish/close them. Do not terminate them. At last check memory
was below the unchanged16GiB +3GiB reserve needed for large replay, so the
supervisor queues rather than lowering memory limits. No production restart
is permitted before validation-v9/passed.json and promotion checks succeed.

User replied that the unrelated Lean jobs must keep running. Left them alone.
Started rocq-mathlib-char-succ-validation.service (Restart=no); startup verified
active/running, finish-status.json phase waiting_for_memory. Required19922944KiB,
available18164336KiB at startup. It pins the candidate before waiting, runs the
complete18-stage validation when admitted, then promotion checks and resume.py
only on success. It does not monitor production after its single startup check.
Log: validation-service.log. Do not edit pinned .ml/.mli/.py/.sh/.v files while
queued/running; the supervisor refuses promotion if its inputs change.
Production remains stopped at30M until the pending qualification succeeds.
