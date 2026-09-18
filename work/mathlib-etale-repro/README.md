# Etale conversion regression, 2026-09-16

Original Mathlib record: **31,651,932**, theorem
`Algebra.exists_etale_bijective_residueFieldMap_and_map_eq_mul_and_isCoprime`.
The production failure was a 1,800-second declaration timeout, not an OOM.
The sealed 30M checkpoint and all dependency proofs remain intact.

## Latest: progress-aware independent-check continuation

v7 passed the full Etale dependency slice, its independent check, all native,
legacy and importer gates, and the original-order30M-to31,651,932 replay.
Stage7 then exited124 because `check.py` imposed1800seconds on the ENTIRE
original-order recheck. The slow `isIntegral_of_isIntegralElem_of_monic_of_natDegree_lt`
proof finished; later declarations were being checked at the cutoff. No type
error or OOM was reported. This is not a completed independent validation.

`check-progress.py` rechecks the SAME artifact and checker binary, using
`scripts/checker_progress.py` inside the unchanged16GiB/no-swap memory guard.
The1800second limit comes from the production plan, but now bounds time without
a new target constant-start event, including startup and finalization. A long
library can complete provided its individual checking steps finish. Arbitrary
output, guard messages and duplicate constant names do not reset the deadline.
Only checker exit0 is success; no declarations are skipped or trusted anew.

The full runner suite passes215tests (2existing skips), including9new deadline
tests. A real guarded checker smoke test passes with6target constants. Kernel
sources/binaries, importer sources, proof artifacts, seals and production's
1800second declaration timeout are unchanged. All previous failed receipts
remain intact; new outputs use `independent-progress.*` names.

`finish-v7-progress.py` resumes qualification at stage7, verifying and reusing
the six successful stages fromv7. All19stages remain mandatory. Conditional
production restart still goes through the complete promotion guard and resumes
from the sealed30Mcheckpoint. There is no recurring production monitoring.

Current continuation status after launch:
`finish-status-etale-v7-progress.json`,
`validation-etale-v7-progress/progress.json`, and detailed checker status
`original-etale-v7/independent-progress-status.json`.

## Current repair: candidate v7

v5 fixed the Etale timeout but failed qualification at the existing
`DiscardedParameters.v` regression: its bare-projection scheduling tried to
compare a costly wrapper parameter that the selected field discards. The
5-second `Qed` limit correctly caught this; production was never resumed.

v7 retains the lazy projection-source comparison described below, but prefers
ordinary delta/projection reduction for a fully applied, transparent constructor
wrapper whose selected field directly forwards the same source argument on
both sides. Recognition is structural: the field must be a variable or a chain
of primitive projections of a variable. Its source arguments are compared by
the existing bounded, read-only syntactic test, with stack relocations retained.
This only chooses reduction order; ordinary conversion still checks the result.
It does not certify equality, ignore arbitrary data fields, or change limits.

Unconditionally exposing every forwarding wrapper (candidate v6) restored the
discarded-parameter test but lost the Etale speedup. That diagnostic replay was
manually stopped after185.591seconds, not timed out or killed by the memory
guard. The narrower v7 rule preserves congruence between different inheritance
paths while exposing wrappers that merely forward an already identical source.

v7 evidence so far:

- `discarded-candidate-v7`:0.561seconds, with both5-second `Qed` checks unchanged;
  unequal payload and genuinely opaque-wrapper cases still rejected.
- `candidate-native-v7`:0.606seconds, projection argument-order regressions pass.
- `candidate-target-v7-production-budget`:230.572seconds including load/save,
  peak1,600,644KiB; the actual Etale theorem passes at the production1800s limit.
- Independent target `rocqchk` rechecking passed180.340seconds, reusing the
  separately compiled dependency prefix (full slice rechecking is still pending).
- `candidate-v7-forwarding-tests.log`: private suite passes, including explicit
  local-binder/stack shifts, partial applications, transparency and unequal
  sources. Environment references are deliberately distinguished from binders.
- Importer source unchanged; `importer.eZWQ15ef` is an ABI-only rebuild.

Worker:`43e004e329587d3669ddd99c153e7220ee710a9e21fcf77909b68c00bfa80227`.
Checker:`446d7476850ade7055dca801a97aaa3eeb1c66abc7049d9eeba53d0119488432`.
Full qualification is tracked by its own receipts. Do not infer a complete
Mathlib pass from these targeted results.

## Underlying v5 strategy (retained in v7)

The change is in `kernel/conversion.ml` in the compact-peano-view worktree.
The original v5 ABI-only importer was importer.ct86AB6s (superseded above).

Adaptations from Lean 4.29's kernel conversion strategy:

- Check source application segments before arguments beyond a projection;
  keep right-to-left comparison within each segment. Precheck every projection
  identity before doing potentially expensive argument comparisons.
- When delta priorities tie with no existing stronger preference, unfold both
  sides one step. Retain existing recursor, dependency and constructor preferences.
- Distinguish bare fields from applied methods. For matching bare projections,
  lazily unfold sources and select the field when a constructor appears instead
  of demanding equality of all fields in the record. Applied methods retain
  their continuation checks and reduction path.

Reference: pinned Lean commit `98dc76e3c0a9b856c9b98726b713fb04fab16740`,
`src/kernel/type_checker.cpp`, `lazy_delta_reduction_step` and
`lazy_delta_proj_reduction`.

This changes conversion scheduling, not the equality rules. Transparency,
universe checks, binder relocation, proof checking, and existing work budgets
are retained. Argument masks stay restricted to well-typed checking. The new
projection helper does **not** cache field equality as whole-source equality.
The ordinary non-Lean-heuristic scheduling remains available unchanged.

## Evidence and limits

- Baseline and v1/v3/v4 fail the exact proof-preserving slice target with the
  short 120-second diagnostic allowance. The baseline also failed production's
  existing 1,800-second declaration allowance.
- v5 passes the exact target with the existing production allowance:
  `candidate-target-v5-production-budget/result.json`, exit0,240.591seconds
  overall including load/save, peak cgroup1,424,780KiB (about1.36GiB).
- v5 still exceeds the short120-second diagnostic allowance. Qualification
  therefore uses the unchanged production allowance of1,800seconds; this is
  **not** a production timeout increase.
- Independent `rocqchk` rechecking of that exact target passed in185.867seconds:
  `candidate-target-v5-production-budget/independent.json`. It reuses the
  compiled dependency prefix; full dependency rechecking remains a later gate.
- Private tests pass for segment ordering, projection identity prechecks,
  unused/used method arguments, bare fields, open binders, transparency,
  negative cases, both comparison directions, and conservative conversion.
- Dependency slice contains every proof, zero abstractions. The reusable prefix
  was checked by v1; full v5 dependency rechecking and original-order checking
  are required before production promotion.

This is not evidence that all Mathlib passes, nor a claim of complete kernel
alignment. The independent checker and full qualification status are in their
receipts, not inferred from compilation success.

## Follow-up batch (v7)

`finish.py` requires the exact target's compilation and independent check to
pass. It then runs a fresh full dependency slice,19 serial qualification stages,
and only then `resume.py` from line30,000,001. A failed check stops the batch.
Only pre-launch memory refusals may be retried; proof failures, timeouts and
OOMs are not retried automatically.

Heavy stages:16GiB hard limit, no swap,3GiB reserve. Production retains its
5M checkpoint interval and1,800-second declaration timeout. No checkpoints
are deleted; unrelated Lean jobs are untouched. No recurring production
monitoring is installed.

The native gate now includes19 fixtures, with `projected_discarded_parameters`
first. Promotion requires all19 fixtures, ordinary/strict independent checking,
the20 legacy and44 importer regressions, runner tests, and all19 serial
qualification stages. Earlier v5 receipts remain preserved as historical evidence.

Launched08:33:29CEST as `rocq-mathlib-etale-validation-v7.service`;
startup confirmed active/running, currently fresh full-slice replay.
Production has not resumed yet. No further source or binary edits while this
pinned batch runs. Progress: `finish-status-etale-v7.json`, then
`validation-etale-v7/progress.json`; full slice log:
`candidate-slice-v7/run.log`.
