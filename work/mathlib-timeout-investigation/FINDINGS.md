# Mathlib timeout: cause and repair

The unchanged proof of `Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq`
checks in **106.923 CPU seconds**, versus the **1,800-second timeout**.
Compilation, saving and fresh reload succeed
([result](focus-default-tgtxuek2/result.json),
[checking log](focus-default-tgtxuek2/run.log),
[reload log](focus-default-tgtxuek2/Reload.run.log)).
The full Mathlib run remains paused.

## Cause

Our custom kernel conversion strategy compared record-wrapper arguments before
reducing projections that discard them. This led into expensive comparisons
of typeclass structures, `Finsupp`, `Finset.filter`, `Classical.choice` and
recursors stuck on the assumption `n : Nat`. It was symbolic conversion,
not evaluation of a large numeral.

The existing `projected_record_wrapper` exception missed three forms:

- `Finsupp.instFunLike`: a function field containing a partially applied getter.
- `Representation.IntertwiningMap.comp`: a constructor behind a `let`.
- `LinearMap.comp`: nested record constructors containing a partially applied
  `Function.comp`, reached through consecutive projections.

Actual translated definitions are printed in `focus-default-qn76mkxx/run.log`
and `focus-default-gzx5doty/run.log`. Conversion traces are in
`focus-default-ndd235_9`, `focus-default-fqs4mgap` and
`focus-default-h80cdxs4`.

## Patch

The [isolated source patch](kernel-fix.patch) changes two areas in
`kernel/conversion.ml`:

- Recognize these forwarding/function fields and follow the pending projection
  chain through nested constructors. Traverse `let` only when the chain
  selects a function-valued field; otherwise retain the old handling of lets.
- Index the unit-like registry instead of repeatedly scanning its 1,248 entries.
  Preserve its existing name equality and rebuild when the immutable registry
  changes, including after undo or reload.

Both restrictions matter. Broader trial implementations passed the Mathlib
theorem but regressed UTF-8 or bitvector-adder fixtures. They were rejected.
The current worker passes both unchanged fixtures:
`utf8-bitvec-two-repro-pis7qnj2` and `blastadd-unary-repro-8s1_4c70`.

No importer definitions, proof bodies, logical rules or checkpoint formats
changed. The projection helper only chooses unfolding order; ordinary kernel
conversion still establishes equality.

## Measurements

| Work | Measured time |
| --- | --- |
| Original proof replayed in Lean 4.29's kernel | 287 ms |
| Importer translation/preparation | about 0.33 CPU seconds |
| Original Rocq target | 1,800-second timeout |
| Patched Rocq target | 106.923 CPU seconds |

The patched process peaked at **4.15 GiB**. The target time excludes loading
its checked prefix and saving importer state.

In the original 1,796-CPU-second failure, dependency queries cost at most
54.09 seconds (3.012%). Building cache entries cost at most 6.58 seconds
(0.366%), included in that total. Cache reconstruction was not the main cost.
This is not the importer's `declared/add_declared` registry.
See [cache measurements](../mathlib-cache-measurement/run-74k2rtgp/REPORT.md)
and [the original-proof Lean replay](Recheck.lean).

The index alone still timed out. Omitting let traversal stalled at conversion
2,140; omitting nested constructor selection stalled at 2,144. The final
worker completes these conversions in about 0.028 and 4.436 CPU seconds.

## Validation

- 20 focused kernel checks pass: `../structured-arrow-repro/patched-checks-2st7_npk`.
- Small positive/negative controls pass: [getters and composition](ForwardedGetter.v),
  [let-bound methods versus computed data](LetMethod.v),
  [nested records](NestedGetter.v), and [registry changes/undo](UnitRegistry.v).
- Original Mathlib theorem checks and its saved module reloads in a fresh process.
- All 44 CSLib/importer checks pass:
  [validation record](cslib-regressions-method-forwarding/passed.json).
  The runner suite also passes: 201 tests run, 2 skipped.

No full CSLib rerun has been performed. These tests do not establish that all
CSLib or remaining Mathlib declarations pass.

## Reproduce

```sh
python3 work/mathlib-timeout-investigation/focus.py \
  --prefix work/mathlib-timeout-investigation/focus-default-xk9vhn0n \
  --line-timeout 300
```

The command uses an 8 GiB guard and records input hashes. Its prefix has checked
every declaration through line 9,239,030; keep it and the original 9M checkpoint
chain. Loading and saving add time to the command.

Tested worker SHA-256:
`e418de461017da8e50eed99d568ca558ecf9d3c2035cb07b8546115387115b2d`.

## Resume the full experiment

From the repository root:

```sh
ROCQ_APPROVED_WORKER_SHA256=e418de461017da8e50eed99d568ca558ecf9d3c2035cb07b8546115387115b2d \
  python3 scripts/resume_mathlib_ndjson.py --line-timeout 1800
```

This selects the tested kernel for continuation from the existing 9M checkpoint,
without changing historical checkpoint seals. The normal single-worker and
16 GiB memory guards remain in place. I have not launched this continuation.
