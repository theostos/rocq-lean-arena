# Next PR: dependent record projections

Prepared on 2026-09-08 as local branch
`candidate/dependent-projections-standalone`, in
`_worktrees/review/next-pr-projections-after`.
Base: upstream `c8db0934f0718e44a66c598360ef9c55ff7d6810`.
The implementation and fixtures come from `199a787`; the universe-instance
commit beneath that historical submission branch is excluded.

The candidate has not been pushed or submitted. A suggested PR description
is in [pr-body.md](pr-body.md).

## Actual before/after errors

On unmodified upstream source, `projection_relevance.v` fails in `Lean Import`:

```text
Error at line 67 (for DepRec.proof): #DEF 14 45 47
Illegal application (Non-functional construction):
The expression "Set" of type "Type"
cannot be applied to the term
 "Set" : "Type"
```

`dependent_sprop_projection.v` separately fails during import:

```text
Error: Error at line 78 (for Subtype.val): #DEF 18 48 52 2
Pattern-matching "let (val, _) := self in val" has relevance mark set to
relevant but was expected to be irrelevant
(maybe a bugged tactic).
```

Both imports, their subsequent exact type assertions, and the existing
`rec_single_ctor.v` and `ulift.v` tests pass on the candidate.

Logs and full commands:

- [Baseline dependent-record failure](before/test-01-projection_relevance.log)
- [Baseline SProp failure](before-subtype/test-01-dependent_sprop_projection.log)
- [Patched run and four passing tests](after/result.json)

The runtime is stock upstream Rocq `56acfe11bcabfc81712ec0191bcbbd7c603e71e5`,
compiled separately under `_worktrees/review/rocq-upstream-runtime-20260908`.
Stdlib is `3e47b26f345f36e375d81ade399eed0e310984b3`, compiled against that
runtime. The existing review harness runs serially under a 3 GiB memory
cap, 6 GiB system reserve, and no swap. No experimental kernel flags or
theorem-specific proof reconstruction are used.

To repeat the patched checks with a fresh output directory:

```sh
python3 _worktrees/review/arena-loop-20260908/scripts/validate_importer_review.py \
  _worktrees/review/next-pr-projections-after \
  --runtime stock \
  --runtime-prefix _worktrees/review/rocq-upstream-runtime-20260908/_build/install/default \
  --stdlib _worktrees/review/stdlib-upstream-20260908/theories \
  --test tests/projection_relevance.v \
  --test tests/dependent_sprop_projection.v \
  --test tests/rec_single_ctor.v \
  --test tests/ulift.v \
  --output work/next-pr-projections/retest
```

The before checkout has identical regression inputs but unmodified upstream
implementation. Its fixtures are untracked additions. The after run was
made before committing the candidate, so `after/result.json` records the
upstream HEAD plus the source diff in `tracked_changes`. `implementation.patch`
records the exact tested source change; committing it does not change the
tested files.

## Relation to the Int64 discussion

The historical missing-constraint error belongs to the retired proof
reconstruction path and was fixed there by `4de13e2`. That function is absent
from upstream and #70, so this is not an outstanding error to fix by
cherry-picking that commit. Our direct imports of the original Int64 proof
on the old #70 parent/head instead timed out; addressing that performance
problem needs a separate investigation of conversion, not the old
reconstruction patch.

PR #70's description should remove its claim to fix the historical Int64
error. If retained, that PR should be described as reducing the exposed
universe parameters; its demonstrated result is an interface change.
