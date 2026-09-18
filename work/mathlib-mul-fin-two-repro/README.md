# Matrix.mul_fin_two: erased proof in a speculative conversion probe

Target: NDJSON line **17,631,905**, `Matrix.mul_fin_two`.

## Cause and repair

The application-congruence optimization copies its arguments and function
prefix into fresh closures before comparing them. An earlier comparison can
already have erased a shared proof application to the internal `FIrrelevant`
marker. That marker is not a term that can be reconstructed as kernel syntax.
Trying to do so triggered the existing assertion in `cClosure.ml:872`.

The baseline theorem replay under GDB identifies the exact caller:
`Conversion.eqwhnf.common_application_congruence.fresh_argument`, formerly
`conversion.ml:1645`. This is not a dependency-cache failure or a timeout.

The repair catches failure only while reifying the argument or prefix of this
optional probe and declines the probe, allowing ordinary conversion to proceed.
It does not catch assertions from the actual conversion checks. The assertion
in `cClosure.ml`, proof checking, dependency heuristics and timeouts are unchanged.

Only `kernel/conversion.ml` and the two new success fixtures
`test-suite/success/congruence_probe_irrelevant.v` and
`test-suite/success/congruence_probe_irrelevant_prefix.v` are part of this kernel fix.
Other worktree changes predate this repair. No importer source was changed.

Baseline worker SHA256:
`9645f46ccef126cb18fbba9f6cbf54356a98cce830e27d2e3190fcbccd6d701e`.

Fixed worker SHA256:
`fdb0d78a70bedd2215f0216bad820f5d745c78129622f8be8c4fabe7e6bc4ad5`.

## Confirmed focused results

- `prefix/`: checked 17,000,001 through 17,631,904, in original order and
  under the original `MathlibTo18000000` module name, with the baseline worker.
  Exit 0; 635.78 seconds including loading and saving.
- `target-baseline/`: the exact next theorem fails at the assertion, with a
  native backtrace through `fresh_argument`.
- `target-candidate/`: the exact theorem checks in **1.077 CPU seconds**;
  exit 0 after 350.67 seconds including loading/saving. Saved `.vo` SHA256:
  `ebc4c3cee521bac0df69b6d89db146b10f0aec69f72e8acc9884de286f8cbd01`.
- `native-constants-baseline/`: a small standalone test reproduces the same
  assertion and caller. Proof applications, not bare proof constructors, are
  needed to expose the mutation of a shared closure.
- `native-candidate/`: the permanent regression passes in 0.56 seconds,
  including both directions, nested proof arguments/prefixes, and negative
  checks for unequal relevant values.
- `native-baseline-final/`: the exact permanent argument regression fails
  on the old worker at the same assertion (exit 129).
- `unequal-relevant-candidate/`: running the negative control without `Fail`
  produces a normal `Type_errors.error_actual_type` rejection (exit 1), not an
  assertion. This checks that the rejection test is not passing accidentally.

## Validation status

The full original-order replay from the sealed 17M checkpoint through
17,650,000 passed and saved in 657.80 seconds. The theorem checks in **0.740 CPU
seconds** in this context (381.725–382.465). Its `.vo` SHA256 is
`8d5d97fa8c36de0dfca11f32a4819a32618acf24fbc0422ec9f3fc98d1901a90`.

`validate.py` passed the fresh reload/save, 24 kernel fixtures,
44 importer fixtures and the runner unit suite (199 passed, 2 skipped).
Results are in `validation-3yinq_w6`, with completion recorded in `passed.json`.
The fresh reload/save took 339.78 seconds, exit 0; its `.vo` SHA256 is
`cabe1d6356a19c49a7fa680de9cf516e6bacfa1bef7283af551082ac0d7fd00c`.
The dedicated prefix compatibility control was added while that gate was running and is
checked separately against the same frozen worker; `resume.sh` requires its
successful result and matching source/artifact too (25 kernel fixtures total).
Its final source passed in `validation-3yinq_w6/prefix-control-final`, exit 0.
`prefix-baseline/` and `prefix-alias-baseline/` also pass on the old worker:
they are compatibility controls, not independent reproductions of the assertion.

`resume.sh` is pinned to that validation and worker. It refuses to resume if
any required success record, source hash or saved artifact is missing or
different. Its read-only `--check` passed before restarting the main loop.
The canonical run was launched from 17M, not the isolated partial 18M snapshot,
under `rocq-mathlib-ndjson-erased-proof.service` on 2026-09-11.
Supervisor log: `work/mathlib-ndjson/erased-proof-resume.supervisor.log`.

All experiments retain the single-worker lock, 16 GiB/no-swap guard and normal
1,800-second per-declaration limit. The 17 original checkpoint seals were verified
read-only. No canonical checkpoint was overwritten by the diagnostic replays.
No commits or pushes were made for this repair.
