# Unit-valued projections through type aliases

The NDJSON run fails at line 5,462,935:
`CategoryTheory.StructuredArrow.homMk._proof_1`.
The last validated checkpoint is 5,000,000.

Mathlib defines `StructuredArrow` as an alias for a comma-category record.
Its discrete morphisms use `ULift (PLift (X.as = Y.as))`, with `as : PUnit`.
The identity on `f.left` must therefore also have the morphism type from
`f.left` to `f'.left`.

## Reproductions

- `AliasedUnitProjection.lean`: Lean 4.29 accepts both the direct record type
  and its transparent alias.
- `AliasedUnitProjection.v`: the previous custom kernel accepts the direct
  case, then rejects the aliased case at `Qed`.
- `ArrowAlias.lean` / `ArrowAlias.v`: the same contrast for the identity
  morphism and nested record projections, matching the failing application.
- `PrefixDirect.v` passes using the actual Mathlib definitions from the 1M
  checkpoint. `PrefixMinimal.v` fails after wrapping the object type in a
  transparent alias.

Each test ran under the memory guard, sequentially, with a 30/45-second limit.
Results are in the corresponding `lean-*.log`, `rocq-*.log` and `prefix-*.log`.
The standalone tests finish in seconds; no library replay is required.
The older `lean.log` and `rocq.log` record an initial unsuccessful reduction
of the problem, not the current reproductions.

## Code path

In `kernel/conversion.ml`, `shallow_unit_like_after_applying` uses
`betaiotazeta` reduction for `inductive_after_eliminating`. The `Zproj` branch
expects an `FInd` head; it does not unfold a transparent record-type alias
before following the projection. That prevents recognition of the unit-valued
result.

## Fix

The patch adds 19 lines to `kernel/conversion.ml`. Before inspecting a projection,
it follows transparent record-type aliases using beta/zeta reduction, with a
32-unfolding limit. Opaque constants, matches and fixpoints are not unfolded by
this extra traversal. The existing dependent-field restriction is unchanged.
There is no option or flag, and no importer or serialized-layout change.

Twenty focused checks pass in `candidate-checks-615ogw99/results.json`, including
the new aliases/negative controls, unit projections, `ModifyEq`, `LinearMap`,
record eta, bounded congruence and arithmetic. For `compact_peano.v`, only the
staged import is narrowed to `NArith.BinNat`: this installation lacks the
`NArith` wrapper; all test assertions are retained.

`run-target.py baseline` and `run-target.py candidate` compare the original
theorem from the 5M checkpoint. Intermediate declarations are deferred, but
the target and every dependency it requests are checked normally. This is a
diagnostic test, not a replacement for checking the entire 5M–6M interval.

The previous worker is retained as `rocqworker.before-alias.exe` (SHA256
`78cfbfb0660e84e0c62e110fd1e60b3262057b815f5f3deda10edf48fccb8ad7`).
The 5M checkpoint remains intact.

## Original theorem

The old worker reproduces the exact `Illegal application` in
`baseline-target-a_de3c7q/run.log`. The patched worker checks the theorem and
saves `Target.vo` successfully (`candidate-target-tsmtbu17/result.json`, exit 0).

The rebuilt main worker is byte-identical to that tested candidate (SHA256
`2d631c655cb65e6b1998886414c36ef10e5a322826b613e338a15009cc090c9f`).
All twenty checks also pass on this main build (`candidate-checks-imh0fdp9/results.json`).
The importer binary is unchanged. No checkpoint seals were rewritten.
The temporary candidate build cache was removed; both test runners now use
the main build. Candidate source and all diagnostic logs are retained.

Resume the full run from 5M with:

```sh
bash work/structured-arrow-repro/resume.sh
```

This pins the tested worker through the existing kernel-migration check and
keeps the 1800-second timeout, memory guard and checkpoint verification.
The disk guard still requires approximately 5 GiB free before starting a chunk.
