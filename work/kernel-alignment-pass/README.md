# Kernel alignment implementation pass

Target: harden the current Rocq kernel against the pinned Lean 4.29 export and
progress the complete Mathlib import, without skipping proofs or weakening
checks. Full acceptance alignment is not inferred from positive import tests.

## Current status (implementation in progress)

- Latest September 13 regression: the gate-19 fresh generation passed 5M and
  10M save/reloads but failed at 11,422,301, `WithTerminal.instCategory._proof_2`.
  Worker `938cf20b10fc8ebcde26d325e797057e79d59e42b1a2078613ff7f53222fe5ac`
  permits bounded ordinary constructor cases in type queries; it retains full
  type/parameter checks and rejects unsupported computation or exhausted queries.
  Consumer importer `importer.lFy9zJVL` is rebuilt from unchanged sources for the
  updated interface digest. The proof-preserving slice (zero abstracted proofs)
  passes and independently rechecks in the existing compatibility profile.
  Strict imported-slice rechecking refuses the pre-existing disabled-elimination
  flags at `autoParam`; this is not counted as a pass or bypassed.
  Gate 20 passes (13 native, 20 legacy, 44 importer, runtime/private and runner
  tests), as do independent native checks in compatibility/strict-with-UIP modes,
  all 11 strict CLI controls and the four-flag/UIP-policy unit test. Original
  context replay through 11.5M passes including save (254.23 s), then fresh
  reload/save passes (36.24 s). Restarted from line 1 in
  `../mathlib-alignment-5m-20260913-with-terminal` with 5M checkpoints and no seed;
  startup verification only, no assistant monitoring. See
  `../mathlib-with-terminal-repro/README.md` for evidence and restart status.
- September 13 regression: the fresh September 12 generation stopped at line
  5,816,190 (`liftToDiscrete._proof_5`), after passing the 5M save/reload.
  Worker `eef8700bf7866f3b04fcd27192b30c96bfe7d71227875a5ce72d001a8d61dfec`
  now recovers full result types for stuck cases, preserving the parameter/type
  checks. The proof-preserving slice, exact original-order theorem and the
  continuation through 6M pass, as does gate 18, but independent checking finds
  missing generic-API eligibility for cases under binders. New worker
  `b02396916069318a4fddd34514ecd937a5294a504384fee31caecfdb62888cb5`
  repairs that discrepancy; both API tests and independent native checks pass.
  Final-build gate 19 passes (12 native, 20 legacy, 44 importer cases, runtime
  tests and 204 runner tests passed/two skipped), as do independent native checks
  in compatibility and strict-with-explicit-UIP modes and the strict CLI controls.
  Final-build original declarations 5,816,190–6,000,000 pass including save in
  170.77 s; fresh reload/save passes in 119.61 s. Restarted from line 1 in
  `../mathlib-alignment-5m-20260913`, service
  `rocq-mathlib-alignment-5m-20260913.service`, with 5M checkpoints and no seed.
  Startup verification only; no ongoing assistant monitoring. About 9 GiB free
  at launch means the disk guard may stop the run before EOF. See
  `../mathlib-lift-to-discrete-repro/README.md` for exact evidence.
  Historical successful 20M+ diagnostics are not a full-prefix validation of
  this new build.
- User-directed restart, 12 September: `full-eta-substitution` was deliberately
  stopped by the user at line 21,116,444 (`Valued.cauchy_iff`). It has no completed
  result; this was not evidence of a kernel failure or VS Code crash.
  The user then requested deletion of all previous Mathlib checkpoints and a
  fresh full run. All 37 audited Mathlib compiled snapshots were deleted,
  reclaiming 6,710,183,007 bytes; sources, exports, logs, seals and unrelated
  regression/CSLib artifacts were retained. Exact targets and hashes are in
  `mathlib-checkpoint-cleanup-20260912.json`. Old artifact references below are
  historical and require rebuilding, not resuming.
  Fresh run: `../mathlib-alignment-5m-20260912`, user service
  `rocq-mathlib-alignment-5m.service`, from line 1 without a seed, checkpoints
  every 5,000,000 lines through the 100,001,405-line export. Uses worker
  `3a9480ea...`, importer `importer.42J4K0w1`, 1,800 s/declaration, 15 GiB RSS,
  16 GiB cgroup and zero swap. Runner tests: 204 passed, two skipped.
  `Restart=no`; model-free logging only, no assistant monitoring/repair loop.
- Previous rebuilt worker:
  `3a9480ea6f86050019bf78e3be3c0dc254ccb96b4cad361e99af1e862dc637dd`;
  checker `7894f0aa99edad27476c4957952b666f4512dcdd54fa943d3015272825e28034`.
  Eta/saturation and raw closure-substitution/atomic-instance fixes are now
  runtime-integrated. `final-gates-16` passes completely with source input hashes
  pinned: nine runtime families, eleven native, twenty legacy, fresh save/reloads,
  44 importer cases and 199 runner tests (two more skipped). Independent native
  checks pass in compatibility (1.78 s) and strict (1.76 s). Strict flag/CLI
  controls pass in `strict-checker-2`; `full-eta-substitution` was stopped by the user.
  No completed large replay exists yet on this build. Historical source-only descriptions below refer to when
  those fixes were first tested.
- `full-shared-budget` passes 21M–22M including save in 1,977.02 s on
  `5fed2fe6...`; artifact SHA256
  `b8c28d98789cc7f65264663c68db489aa7ad2b52d45d09b41baac511e69998dd`.
  Both 21,660,881 and 21,692,183 pass. Reload/save passes in 421.34 s,
  artifact `21d67758ee5036f56006daa55ade8b576af8407f8851f32c3587e14f560596ed`.
  This is diagnostic
  evidence, not a promoted or final validated checkpoint: the expanded direct
  API counterexamples below fail this build. Its compiled snapshots were later
  deleted at the user's request, as recorded above.
- Additional source-only sharing repairs: atomic universe instantiation avoids
  forcing an unused memo table (696,096 to 400,096 bytes for 1,000 roots), and
  `CClosure.subst_constr` memoizes raw syntax by identity and binder depth
  (71,304,024 to 10,200 bytes on the 18-level shared fixture). Source suites pass;
  runtime integration and expanded gates remain pending.
- Source-only eta follow-up: the new `WitnessBox (ParamUnit A/B)` direct API
  negative fails the executing runtime's eta mask and passes after removing
  that mask. A second private negative covers an opaque projection under the
  explicit elimination-relaxed compatibility profile; old candidate
  `witness-candidate.CpA50XHl` accepts incompatible parameters, source candidate
  rejects them and passes matching-type controls. Full private suite passes.
  Not runtime-integrated during `full-shared-budget`; see report for scope.
- Preceding worker: `5fed2fe6de659ee3e36a63d49cc372f3d7a03cfcbdda3899ca3d6160b9199cb1`.
  Raw syntax sharing, module-array traversal and nested dependency budgets are
  integrated. All nine runtime test families pass. `utf8-shared-syntax` passes
  in 5.02 s including save; `int32-shared-syntax` passes the complete fresh input
  in 86.28 s including save. `final-gates-15` passes all native/legacy/importer,
  fresh save/reload, private/runtime and runner gates. Independent native checks
  pass in compatibility (2.21 s) and strict (2.13 s) profiles. `full-shared-budget`
  now saves successfully, as recorded above. The canonical generation is unchanged.
- Checker `087f0738...` adds opt-in `-strict` and explicit `-allow-uip`;
  disabled guard/positivity/universe/elimination checks and admission options
  are rejected. `strict-checker-1` passes eleven CLI controls; the direct
  CheckFlags unit additionally covers the elimination flag. This policy does
  not settle the importer's conditional elimination-relaxation obligation.
- Preceding worker: `20c123da6294a4b235f1dd5aa02c88d4e494313292cc998f767e81e64b8d6d05`.
  `utf8-certified-heights` passes including save in 5.03 s;
  `int32-certified-heights` passes the full fresh input in 88.79 s, peak
  294,312 KiB. The 70,000-node height-eviction test passes; the two-unit negative
  test fails against the saved preceding module and passes against this one.
  `final-gates-14` passes the complete gate: eleven native, twenty legacy,
  six runtime families/private tests, fresh small save/reloads, all 44 importer
  fixtures and 199 runner tests (two additional tests skipped). Independent
  checking of the eleven native artifacts/dependencies passes in 1.90 s.
  `full-certified-heights` was stopped after 1,374.77 s (exit 143), around line
  21336923, for persistent dependency-search cost. No checking failure,
  declaration timeout or saved 22M artifact. Runtime rebuilding of the next
  candidate begins only after confirming every replay child has exited.
- Now-integrated follow-up: sharing-aware raw lifting, occurrence checks, de
  Bruijn/named/universe substitutions, and module substitution; array traversal
  is repaired in the latter. Actual renamed-module candidate tests pass. Old
  runtime negative controls fail the allocation/sharing and array-rename tests;
  its shared closedness test times out at 10 s. These changes were not in
  `20c123da...`; that replay finished before rebuilding. Three new test families
  are included in `final-gates-15`. See the implementation report for
  measurements and the remaining hash-collision/stack-depth caveats.
- The integrated conversion candidate shares the indirect probe's 1,024-unit budget
  with nested graph search. Compact eligibility completes closedness/alias
  inspection before dependency queries. Private deferred-witness and existing
  conversion tests, focused arithmetic and integrated gates pass. Large-corpus
  scheduling performance is being measured in `full-shared-budget`.
- The source restores the validated scheduling policy after `final-gates-13`
  stalled at `Int32.toBitVec_div`, line 89636 (deliberately stopped, exit 143).
  Certified dependency-height pruning now passes the dependency suite, including
  two-work-unit cross-DAG negatives and missing/partial/cyclic controls.
  Runtime integration plus focused UTF-8/Int32 replays pass.
- Rejected worker: `ff8a84ac4a041bb71b22b8b3c5ea585b96d5b8b319be519c984f43e56453b199`.
  Narrow wrapper recognition is restored. Unequal priorities retain direct
  occurrence and constructor-argument preferences; only ties run transitive
  graph queries. `utf8-priority-constructor` passes the isolated UTF-8 target
  including save in 5.04 s, under the unchanged 30-second line limit.
  `priority-direct-final` passes the direct-dependency fixture in 0.61 s.
  `final-gates-13` later stalled in Int32 and was rejected. Prior candidates:
  `final-gates-12` passed eleven native fixtures, twenty legacy fixtures,
  all runtime/private tests and fresh small sealed save/reloads, then 28
  importer fixtures. UTF-8/bit-vector `Fresh` timed out at line 146567 under
  the unchanged 30-second limit. Not promoted; focused isolation is ongoing.
- `final-gates-11` caught a five-second `direct_unfolding_dependency.v` timeout:
  scalar priority alone can evaluate an expensive function before exposing
  its record wrapper. The wrapper recognizer now selects constructor fields
  without evaluating their contents, with bounded stack/body inspection.
  The formerly failing fixture passes on the revised build.
- `full-dependency-memo` was stopped after 872.29 s (exit 143), around
  21329038. Dependency searches remain prominent; no checking failure, timeout
  or saved 22M artifact. A source candidate restores unequal oracle-priority
  precedence over lazy dependency/constructor tie probes. Private ordering and
  existing witness/cache/quotation tests pass.
- The original failure at 21660881 passes in `target-snapshot`, including save.
- `final-gates-6` passes on the preceding worker (`796f7179...`): ten native and twenty legacy
  fixtures, all six unit families and private budget/cache tests, digest
  rejection tests, a fresh small import with reloads, 44 importer fixtures,
  and 199 runner tests (two additional tests skipped).
- Independent checking of all ten newly compiled native artifacts and their
  dependencies passes in 1.79 seconds, without `-admit` or `-norec`.
- `full-final` passes 21660881 in 130.08 process-CPU seconds, then fails at
  21692183 with an illegal application (the earlier projection assertion is
  gone). Wall time 753.47 s; cgroup peak 9,977,320 KiB. No 22M save.
- A new dependent-projection fixture fails at Qed on that binary. The current
  worker (`c1419eb7...`) uses the actual record in full unit-type witnesses;
  positive and incompatible dependent-type direct tests pass, including a
  function returning the record. The native fixture passes at Qed. The focused
  Mathlib declaration passes including save (`projection-subject`, 466.20 s,
  peak 8,852,416 KiB, artifact
  `bae5423767a813de8e4d7a4156fb19f3d9d2bb9031280c01657dd8d7d5b17ed5`).
- `final-gates-7` catches an opaque-alias negative-test regression in that
  candidate. The full-type query now intersects caller and oracle transparency.
  `final-gates-8` passes on `a4a85a6c...`: eleven native fixtures, twenty legacy
  fixtures, six runtime unit families/private tests, fresh small import/reloads,
  all 44 importer fixtures and 199 runner tests (two additional tests skipped).
  Independent checking of the eleven native artifacts/dependencies passes in
  1.80 s without admitted dependencies or `-norec`.
- `projection-prefix` saves through 21692182, with predecessor `prefix`.
  Its `.vo` SHA256 is
  `1cc035733aa3491c48f822f052ede632af9426abd9bc817a07c41ad69d6e99ce`.
  For the next focused replay use `ROCQ_ALIGNMENT_TARGET_LINE=21692183` and
  `ROCQ_ALIGNMENT_EXTRA_PREFIX=.../prefix` with `--prefix .../projection-prefix`.
  Extra prefix source/artifact/records are checked and pinned independently.
- Its full replay (`full-witness`) caught a new open-type reconstruction error
  at 21071018 (`HahnSeries.ofPowerSeries_apply`): reconstructed local neutrals
  were incorrectly treated as environment-relative definitions.
- `unit_type_witness.ml` now reproduces that error with an applied local type
  function. Rebuilding with the correct local identity substitution passes;
  `full-witness-context` passes that declaration and 21660881, then finds a
  speculative projection array error at 21692183. A microtest reproduces it;
  the compiled query-only guard declines malformed/partial projection views.
- Named parameters, local binders, applied local type functions, constructors
  and incompatible universe instances are covered by direct conversion tests.
- Compiled and tested: common-type reclassification, isolated flexible-result
  queries, alias transparency, projection query safety, and unconditional
  dependency digest checking.
- Constructor-DAG lifting now allocates 6,192 bytes on the 20-level fixture,
  versus 117,440,536 bytes on the baseline. Quotation, snapshots, substitution
  inspection, lifting and type-witness unit families pass.
- `final-gates-3` passes all 44 importer fixtures and 199 runner tests (two
  additional tests skipped), including a fresh small 1,128-line import and
  three sealed chunk/reload pairs. This is not a fresh Mathlib prefix.
- Compiled: bounded pair-indexed projection caching, explicit local type-lift
  keys, bounded local-definition query lifting, and query relevance-mask
  avoidance. Snapshot-based ordinary application congruence was rejected by
  integration testing and reverted; snapshots remain the type-query mechanism.
- Ordinary application congruence retains syntax quotation, now preflighted
  under one 65,536-expanded-node allowance across both arguments and prefixes.
  The 4,096-node type-witness allowance was too small here. The independent
  application allowance passes `AdjacentTrace` in 26.70 s under a 10-second
  declaration timeout; exact-bound and oversized-DAG tests pass.
- Conservative checker conversion now receives the same wrapper delta-order
  preference as ordinary typing, without adopting the typed conversion API.
  Independent checking passes again on the final artifacts
  (`final-gates-6/independent-check.json`). This is
  not a strict theory-profile check; that profile is still outstanding.
- Original importer binary and canonical checkpoint seals remain unchanged.
  The staged importer is an explicitly pinned diagnostic consumer. A fresh
  generation from line 1 is required for a new full-pass claim.
- Disk space is approximately 5 GiB; cleanup approval is outstanding. No old
  checkpoints or user artifacts were deleted during this pass.
- The dependency-cache source candidate replaces transitive bitsets with
  capped direct edges and pair answers. Shared-fuel exhaustion is explicitly
  unknown. `test-dependency-candidate.sh` passes the existing graph/fork/reload
  suite plus budget, wide-term, cycle and storage-cap controls. Integration
  rebuilt successfully; `final-gates-9` passes all eleven native, twenty legacy,
  six runtime unit families/private tests, fresh small import/reloads,
  44 importer fixtures and 199 runner tests (two additional tests skipped).
  Independent native checking passes in 1.82 s. Current worker `4d9c3e39...`,
  compatible isolated importer `importer.42J4K0w1`.
- `full-dependent` was stopped after 1266.99 s (exit 143), around 21372595,
  for a performance regression; no checking error or declaration timeout was
  reported and no 22M artifact was saved. Full samples/logs are retained.
  No diagnostic prefix was used as its starting state.
  The preceding gate's hour-long wall-clock gap was a confirmed host suspend
  (18:08:58–19:13:12), not a kernel slowdown.
- The revised dependency source memoizes completed negative subgraphs and
  reuses stable answers across ordinary environment extensions, with per-answer
  stability propagated through eviction. Standalone overlapping-query,
  replacement, cyclic escape and unstable-answer eviction tests pass. Rebuild
  succeeds (`b2c71ad3...`), and `final-gates-10` passes all eleven native,
  twenty legacy, six runtime families/private tests, fresh small save/reloads,
  44 importer fixtures and 199 runner tests (two additional tests skipped).
  Independent native checking passes in 1.80 s, with the same compatible
  isolated importer. Do not treat the stopped build as final.
- `full-dependency-memo` is now replaying the whole 21M–22M segment on that
  corrected build, with the diagnostic sampler. Save/reload remain pending.
- Removed 155 disposable test executables produced by this pass (about
  1.3 GiB), retaining sources, objects, scripts and all proof artifacts/logs.
  They are rebuildable. Free disk space after this cleanup is about 6.4 GiB.

The following sections preserve the chronological test record; earlier
“prepared” or “in progress” entries describe those stages, not current status.

Earlier checkpoint in the chronological record, worker SHA256:
`b2c71ad332cfdcb866e5d25ec8da10457a6d039cd21412020eda02252a33e27f`.
Its preceding complete gate worker SHA256:
`a4a85a6c38710590bd5054a42383bed21a0789fbdb4d3e5959dd8eaafb06fee1`.
Current diagnostic importer: `importer.42J4K0w1`, plugin SHA256
`b17738e6278ee0df0984fbdac06653001f1a1d29eb046bb2f241d86f1d5d4cde`.
Earlier `importer.ppBaeRqL` and `importer.brtcQ36Y` are preserved, but are not
ABI-compatible with the current kernel interface.

## Initial plan

Starting state: canonical chain sealed through 21M; attempt
20260912T100206892784Z failed with exit 125 at line 21660881,
AlgebraicGeometry.Scheme.Pullback.ofPointTensor_SpecTensorTo. No worker remains.
The sampled stack shows closure quotation/substitution, not the initiating query.

Implementation sequence:

1. Reproduce and fix quality registration and arithmetic update-frame defects.
2. Test/fix dependent registration replay and full declaration contexts.
3. Capture the new theorem's full initiating stack using the guarded harness.
4. Implement general closure/sharing and conversion changes justified by pinned
   reference behavior, with negative/context/budget tests.
5. Validate previous failures, fresh reload, strict checking, then resume the
   canonical loop. Continue on subsequent structural failures.

Baseline worker SHA256:
0531151b6f83a927b0c3caad2fa56190f21defa5409cd7cf4933eedf30a4248d.
Existing source changes are preserved. No commits or pushes are authorized.
One guarded Rocq worker at a time; retain memory, timeout and no-swap limits.

## First correctness gate

The three initial baseline fixtures reproduced their intended failures:

- `baseline-quality`: exit 1, unsafe registration unexpectedly accepted.
- `baseline-sharing`: exit 1, computed `PZero` used as a function.
- `baseline-registration-order`: exit 129, `Primred` assertion at module end.

All three pass with worker
3a089398a6b6351e92886a93eb92bfe3969883db7162ff42b5eb7315c064551d
in `fixed-quality`, `fixed-sharing`, `fixed-registration-order` respectively.
The changes require definite irrelevance, preserve function update boundaries,
and replay registrations oldest first with a structured missing-scheme error.

`baseline-universes` also reproduced acceptance of an invalid phantom-universe
builder (exit 1 at the expected-failure command). The full-context validation
repair is prepared but has not yet been built/tested. The prefix replay is
using the preceding worker; it must finish before any binary rebuild.

## Scheme pullback replay

`prefix` passed: 943.56 seconds, prefix `.vo` SHA256
789b690eac4615cfa72127e4682cb21f6d50fc6250b2ed89de5cbeb4b53d5333.
It checks 21000001 through 21660880 against the preceding worker.
The isolated `target-before-quotation` replay is in progress using that same
worker and the full-stack GDB sampler. The worker remains unchanged.

A per-quotation closure/relocation cache is prepared, but not built or validated.
The baseline quotation fixture fails its physical-sharing assertion. The test
also covers distinct relocations, substitution under binders, subsequent cell
mutation, and shared DAGs represented both as applications and substitutions.
This is not yet evidence that the Mathlib failure is fixed.

`target-before-quotation` failed with guard exit 125 after 251.06 seconds.
Full stacks identify `same_unit_like_flex_rel` as the initiating caller.
Quotation sharing alone (`target-quotation`) also failed with guard exit 125,
after 223.25 seconds: lifting quoted syntax still expands sharing.

The quotation unit tests pass (40-level application DAG: 10,760 allocated bytes;
substitution DAG: 33,224 bytes). All four correctness fixtures pass on worker
9cc644f3fed904e9e32a9d15886d38d904893137e0b83f883d8b9580d127c440.

The next implementation replaces speculative unit/eta reification with bounded
closure snapshots. It preserves substitutions and sharing, isolates mutable
cells, shares a budget across copying/head steps, and declines unsupported
computation. `closure_snapshot.ml` passes its 50-level DAG, relocation, isolation,
repeated-call budget and nonterminating-beta-query tests (18,816 bytes).
The old quotation preflight and unused abbreviation helper were removed.
The fallback that stripped products without substituting actual arguments was
also removed; the focused conversion regressions must validate the impact.

The interface changes require rebuilt plugins. The first native fixture against
the new worker failed to load an old core plugin (`interface mismatch on Vars`),
before checking any theorem. Core plugins are being rebuilt. An isolated importer
source copy is staged under `importer.ppBaeRqL` and rebuilt there. The original
importer binary, checkpoint sources, seals and toolchain manifest are untouched.
Use `ROCQ_ALIGNMENT_IMPORTER` for diagnostic replays only; the wrapper pins this
consumer plugin/source separately while still checking all original producer
seals. This is not approval to continue the canonical generation with a changed
importer, nor independent rechecking of its earlier proofs.

`snapshot-compatible-*` (nine fixtures) and the 20-fixture legacy kernel suite
(`work/structured-arrow-repro/patched-checks-yoc7c9jo`) pass on worker
c8f83a27e59ac637dedbcd7088986b22b10f6f04ac4c5730828b794fe6b09cf6,
using staged importer SHA256
f525dbb22d85e135681e9bcbbfa75bf0376d1df39fee1d72250bc5f23245c276.
`target-snapshot` passes completely: 695.52 seconds including load/save,
quickdef finishes at process CPU 365.62 s (starts at 93.38 s), cgroup peak
11,702,136 KiB, `.vo` SHA256
37dfeaba1c3dea9eaeb85cabc375ffceea12e1c85a1845ac19df3f178c584f1f.

The C3 API-level defect is now reproduced by `unit_type_witness.ml`: a safely
declared fieldless `ParamUnit (A : Set)` accepted conversion of `x : ParamUnit A`
and `y : ParamUnit B`, although the types themselves do not convert. This is
not an end-to-end false theorem. A candidate repair requires full instantiated
type conversion and retains local-domain relocations. Standalone compilation
of the candidate passes named-variable, constructor and nested-binder positive
and negative tests, for both public conversion modes. Integration is pending.
The occurrence guard is retained solely for the bounded relocation interface
used by this full-type witness, not general unit/eta type classification.
