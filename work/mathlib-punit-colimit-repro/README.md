# PUnit colimit: unit-like types behind aliases and projections

Failure: NDJSON line **13,066,340**, `CategoryTheory.Limits.punitCoconeIsColimit._proof_4`.

The expected equality is `m = eqToHom (...)`; Lean supplies `eq_refl m`.
The rejected `id_inst1` application is the enclosing symptom, not a broken
identity function. The type of the arbitrary morphism `m` is hidden behind
`Hom`, `toQuiver`, `toCategoryStruct`, and `discreteCategory`. Selecting the
concrete category's morphism field exposes `ULift (PLift P)`, a primitive
record wrapping a registered proof-only unit. Its inhabitants are convertible
under the existing record-eta and registered-unit rules.

The [previous repair](../mathlib-punit-ext-repro/README.md) recognized the
exposed wrapper type but did not follow these applied aliases/projections in
the local variable's type. The transitive-dependency cache is unchanged.

## Reproduction and repair

- `alias-baseline/result.json`: old worker rejects `Wrap (ProofBox P)` even
  though `Wrap A := A`; the unwrapped case passes in the same source.
- `target-baseline/result.json`: old worker reproduces the reported failure
  after replaying 13,061,817–13,066,340 from the prior validated prefix.
- `conversion.baseline.ml` and `rocqworker.baseline.exe`: preserved previous
  implementation and worker (`a391359995f9406156307448b6356d4ff5e80b28f053850b6ae95632d8c5e78e`).

Only `kernel/conversion.ml`'s `unit_like_type` query changes. It now follows
transparent constant bodies with their arguments, and selects primitive
record fields from constructors. The existing 32-step budget also covers
these additional steps. Ordinary beta/zeta reduction is retained, but this
new inspection does not evaluate matches, fixpoints, cofixpoints or primitives.
Opaque definitions and projection transparency are respected. Extra unfolding
does not update shared conversion closures: update frames are discarded before
the new alias/projection steps, and the reduction table remains isolated.

Record instantiations still require every field to be irrelevant or unit-like;
the conservative check against scrutinee-dependent field types is unchanged.
No importer, proof, checkpoint, cache, timeout or memory-policy changes.

New regression: `test-suite/success/unit_like_aliases.v` in the kernel worktree.
It covers nested aliases, a category-shaped morphism type, both equality
directions, opaque canonical values, registered non-record units, and both
dependency-heuristic settings. Negative checks retain relevant data and unknown
parameters, preserve opaque aliases/categories and dependent fields, and reject
an expensive recursive type query within a five-second limit.

## Validation

Gate: `python3 work/mathlib-punit-colimit-repro/validate.py`.
Artifacts: `validation-qgnl0pow/`. Validation is complete only when that
directory contains `passed.json`; logs alone or the native test's success do
not establish that the original Mathlib replay passed.

Required stages:

1. Both wrapped-unit and alias/projection kernel regressions.
2. Original module name and sequence, 13,000,001–13,100,000: includes both
   reported failures and another 33,660 NDJSON lines beyond the newer failure.
3. Fresh-process require, importer state unpack and re-save of that artifact.
4. Twenty existing kernel fixtures, 44 importer/CSLib fixtures and runner tests.
5. Source/worker checks and read-only re-verification of all 13 canonical
   checkpoints, using the sealed plan without regenerating its sources.

All stages passed on 2026-09-11. `validation-qgnl0pow/passed.json` records
the validated worker and source hashes. The original-order replay and save took
267.57 seconds (4.62 GiB peak); fresh reload, state unpack and re-save took
247.85 seconds. All 22 kernel files and 44 importer/CSLib fixtures passed.
The runner suite ran 201 tests in 13.35 seconds, with two skips and no failures.
All 13 canonical checkpoint verifications passed; the only producer/current
input difference was the explicitly validated worker migration.

Validated worker: `4c35ea0349dc0cb1c22d7d80acc6a456b9de9f31851af26be7868404f72415b3`.

`kernel-fix.patch` isolates this repair relative to the saved baseline;
`git apply --reverse --check` passes against the patched kernel worktree.

## Resume

The user previously requested resumption after validation. The helper refuses
unless the complete gate, replay range, worker, source hashes and saved artifacts
match:

```sh
bash work/mathlib-punit-colimit-repro/resume.sh --check
bash work/mathlib-punit-colimit-repro/resume.sh
```

The normal runner resumes from the canonical 13M checkpoint, not from this
partial diagnostic artifact. Limits remain one worker, 16 GiB/no swap and
1,800 seconds per declaration. No canonical checkpoint is replaced by the
diagnostic replay.

Resumed after validation on 2026-09-11 at approximately 09:56 UTC via
`rocq-mathlib-ndjson-unit-alias.service`. The service was confirmed active in
startup preflight, with `checkpoint_through: 13000000`. Supervisor log:
`work/mathlib-ndjson/unit-alias-resume.supervisor.log`. This is not a claim
that the remaining full Mathlib run has completed.
