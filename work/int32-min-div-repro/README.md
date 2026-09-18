# Compact fuel: `Int32.minValue_div_neg_one`

The full cslib continuation passed the previous HashMap blocker and stopped at
line **13,744,561**, `Int32.minValue_div_neg_one`, with a stack overflow.
It remained below the memory cap.

## Cause and correction

The unchanged Lean proof is `rfl`; checking it computes signed division.
The experimental kernel already has validated compact division/modulus
workers, but its two entry paths prepared their arguments differently.

`unfold_ref_with_args` only head-reduced the arguments. For fuel of the form
`S (computed dividend)`, the predecessor could remain unevaluated. The compact
worker was then missed and ordinary recursive division accumulated stack frames.

The fix uses `compact_peano_reduced_fconstr`, the existing probe used by the
reduction machine, for the divisor, fuel and dividend. Registration validation,
the nonzero-divisor and sufficient-fuel checks, arithmetic formulas and fallback
are unchanged. No importer or library proof changes; no new axiom or higher limit.

The kernel delta is on local branch `fix/compact-fueled-arguments`, based on
`fix/direct-unfolding-dependency` (commit `b4db6046c3`); it is also built in the experimental worktree.
The branch has not been pushed.

## Evidence

- `MinDiv.lean-export`: 15,560 lines, exporting the original theorem and its
  dependencies with Lean 4.27.0-rc1. No replacement proof.
- `Target.baseline.*`: timeout at 30s with the previous worker.
- `Target.short-stack.*`: same stack overflow with an 8 MiB diagnostic stack.
- `Target.stack-trace.*`: temporary, bounded diagnostics locate the recursive
  arithmetic evaluation. Those kernel diagnostics were removed afterwards.
- `Target.compact-fuel.*`: succeeds with the same 8 MiB stack; import finishes
  at 0.82 CPU seconds. Default-stack verification passes too.
- `Fresh.compact-fuel-regressions.*`: fresh import of all 377 entries passes.
- `Widths.compact-fuel-regressions.*`: unchanged Int8, Int16, Int32 and Int64
  `minValue_div_neg_one` proofs pass. The saved modules reload successfully.
- `Arithmetic.compact-fuel-scope.*`: six quotient/remainder checks pass,
  including both directions and division/modulus by zero; three incorrect
  results are rejected at `Qed`. The first attempt lacked the `N` notation
  import; its failed setup log is retained separately.

`run-regressions.sh` runs these checks and the 20 earlier HashMap, Int32,
FinLoop, unit-projection and importer checks, sequentially under memory guards.
All 25 selected checks passed (tag `compact-fuel-regressions`, with the
arithmetic setup correction retested under `compact-fuel-scope`). It does not
launch the full cslib continuation.

`../unit-projection-repro/check-prefix.sh compact-fuel` also passed: the original
11-million-line checkpoint loads and a dependent module saves successfully.
All historical input hashes still match. This establishes load compatibility,
not fresh rechecking of all saved proofs.

## Resume

The existing launcher pins the new worker and preserves the historical prefix
and input manifests:

```sh
bash work/unit-projection-repro/resume-cslib.sh
```

It resumes from the saved checkpoint at **11,005,951**, not the failing line.
Limits are unchanged: one worker, 16 GiB hard cap, 15 GiB preventive RSS limit,
3 GiB system-available reserve, no workload swap. No full continuation was
started during this fix; full-library completion remains unverified.

## Reproduce locally

```sh
bash work/int32-min-div-repro/run.sh Prefix UNIQUE_TAG
bash work/int32-min-div-repro/run.sh Target UNIQUE_TAG
bash work/int32-min-div-repro/run.sh Arithmetic UNIQUE_TAG
```

Each tag must be unused for that test. Export scripts also require unused
output names and must be invoked through `work/run-memory-guarded.sh`.

```text
previous worker: 829aff8548eb3d9f614130de284a1f659411929a404ec2375c85cb4daef612c5
patched worker:  00d7abf71ecd1070756e9258d23054f1a7cb95113a9b9f8ce3450e93f28a7912
MinDiv export:   5eb16ad81f0174356ea9cb9087328aee3fae8027bf9158df7f08881da494c035
Widths export:   c695bdccef47534a5f18aaf35cbfa187c40a5aadc08e68316d7a0726a21d6845
```

These are checks of the experimental kernel, not stock-Rocq validation or a
soundness certification.
