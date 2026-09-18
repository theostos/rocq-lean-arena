# Riemannian type-query continuation, 2026-09-15

Status (17:52 CEST): candidate built, but validation batch `validation-v11`
FAILED its first Riemannian stage at 25,505,940 under the unchanged 120-second
declaration limit. No production restart was attempted. The native
representation reproducer fails before and passes after this patch, but that
improvement is not sufficient to fix the Mathlib regression.

The v11 replay took 716.76 seconds at the stage level; the guard's cgroup peak
was 8,229,668 KiB, below the 16 GiB cap. Both its final diagnostic sample and
timeout backtrace show `Environ.constant_depends_on` beneath
`Conversion.indirectly_depends_on` / `dependency_preference`, inside application
type checks. This is evidence of remaining dependency/conversion work, not an
OOM and not a complete cost profile.

Follow-up diagnostic service: `rocq-mathlib-riemann-diagnostic-v11.service`.
It replays the existing prepared prefix with observational conversion entries
and Typeops cache counters into
`../mathlib-riemann-sharing-repro/riemannian-query-diagnostic-v11`.
The source, worker and timeout are unchanged. This prepared replay is for
diagnosis; any fix still needs the uninterrupted original-order replay.

## Failure evidence

Batch v10 passed its first12 stages: alias, both Char slices, independent Char,
the uninterrupted original-order30M–30,806,240 segment and independent check,
SSet, Lie, derivative and their independent checks. It then timed out under the
unchanged120-second declaration limit at25,505,940,
`Bundle.ContMDiffRiemannianMetric`. No production restart was attempted.
The guard peak was7,662,404KiB, below the16GiB ceiling; this was not an OOM.
The final backtrace is in
`../mathlib-riemann-sharing-repro/riemannian-succ-final/run.log`.
It shows `with_closure_snapshot.copy` / `Esubst.map_subs` recursively copying
captured environments for `same_unit_like_flexes` before ordinary unfolding.
Other samples also show conversion work, so the snapshot is a demonstrated
cost defect, not a proven explanation of all time spent in this declaration.

## Adaptation

Pinned Lean4.29 commit98dc76e3c0a9b856c9b98726b713fb04fab16740:
`src/kernel/type_checker.cpp`, `is_def_eq_unit_like`, `infer_type_core`, `whnf`.
Lean inspects immutable expressions and caches reduction/inference separately;
it does not deep-copy captured Rocq closure environments before type inspection.
This is a representation-level adaptation, not exact algorithm equivalence.

`with_private_closure_query` applies the existing private call-by-need mechanism
to bounded optional type-head queries. It shallow-copies roots and copies a
nested cell only when the head machine demands it. Copied cells retain sharing
within that query. Captured substitutions/arrays remain borrowed immutable
structure. The query retains its4,096-unit work bound; exhaustion is still
inconclusive. No equality rule or checking flag changes.

Policy-dependent neutral marks are reactivated only in the private query;
constructor/lambda/fixpoint marks retain their intrinsic meaning. Caller-owned
update frames are removed by the existing stack reconstruction. Callbacks must
use the supplied reduction infos and fresh tables. This is not an eager deep
snapshot for arbitrary mutation under unrelated infos: the original eager API
remains available with its existing contract and tests.

The restricted head machine now explicitly declines encountered locked cells
and bare higher-order substitutions, rather than reaching an assertion/anomaly.
Ordinary non-query behavior is unchanged.

## Focused verification

- New `type_query_sharing_test.ml` failed on the old kernel at its first large
  unused-environment query. After the change, environments with1/256/8192/32768
  entries all require exactly2,440 allocated bytes for the query itself.
- Open-term relocation/substitution agrees with the eager snapshot reference.
- Repeated roots share an owned cell; source terms and caller update cells stay
  unchanged on success and exhaustion. Demanded work and wide interfaces remain
  bounded. These are representation tests, not standalone typing judgments.
- Full witness suite, existing quotation/closure/dependency/substitution tests,
  and all32 checked-fixture demanded-major tests passed.
- Worker/checker and core plugins rebuilt. `importer.VaaBDebc` is an ABI-only
  rebuild of the unchanged sources from `importer.k9WSHRtn`.

Candidate worker9cc329f53f980bc400264c1a82f80b9cc8c2fbc2e112787c8f057dfefff81462.
Checker42b0a9a658d0399f16b49e39fc822360980b0e5a4a054f87bf77d88b48899f1b.
Old binaries are preserved as `pre-type-query-worker.exe` and
`pre-type-query-checker.exe`; all old validation/checkpoint artifacts remain.

## Pending validation / restart

Batch v11 reruns all18 stages on this worker, with the Riemannian segment and
its independent check first. It does not reuse old successes as current-worker
qualification. `finish.py` invokes `resume.py` only after every stage succeeds.
Resume remains from the sealed30M checkpoint, with5M intervals and1,800-second
production declaration limits. Heavy jobs retain16GiB/no swap plus3GiB reserve;
small Char checks use8GiB. Unrelated Lean experiments are untouched.
Check `finish-status.json`, `validation-v11/progress.json`, and
`validation-service.log` before taking any further action.

Full Mathlib verification is still incomplete. Do not describe this candidate
as fully aligned, fully validated, or a complete Mathlib pass.
