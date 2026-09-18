# Stuck record eta: LRAT restore assignments

The full continuation fails at **15,281,867**:
`Std.Tactic.BVDecide.LRAT.Internal.DefaultFormula.restoreAssignments_performRupCheck_base_case`.
The failure is a type-conversion error, not resource exhaustion. See the
[original log](../cslib-full-fresh/runs/cslib-unit-fix/attempt.gLXfiHDh/Complete15M.run.log).

Find the failing declaration without printing the full error:

```sh
rg -n -m 1 'Error at line' work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.run.log
```

## Cause and fix

The proof compares an array/list element with a pair reconstructed from its
projections. The comparison reaches a record-valued computation stuck on a
variable. Our early-eta optimization cannot infer its result type through
every elimination stack, and had removed Rocq's original fallback when the
head cannot unfold.

Restore that fallback in both directions. It uses the original
`eta_expand_ind_stack` and compares the resulting fields. No new equality rule,
importer patch or replacement library proof.

Local kernel branch: **`fix/stuck-record-eta`**, commit **`066b95cc9b`**, based
on `fix/constructor-wrapper-conversion`; not pushed. The live kernel contains
the same source delta. These are experimental-kernel checks, not a soundness
certification or a stock-Rocq validation.

## Evidence

- `Restore.lean-export`: original theorem plus dependencies, 138,299 lines,
  exported with Lean 4.27.0-rc1. Prefix: 1,815 declarations.
- `Target.baseline.*` reproduces the same error. Disabling the dependency
  heuristic also fails (`NoHeuristic.baseline.*`).
- `Target.trace.*`, conversion call 484, reaches a stuck elimination while
  comparing a projected value with a subtype constructor; the fallback is
  missing. This tracing uses existing opt-in diagnostics, not a temporary patch.
- `Target.eta-fallback.*` passes: 1,816 declarations; target checking completes
  at 1.60 CPU seconds, including loading the reduced prefix.
- `StuckRecordEta.baseline.*` reproduces the missing eta without the importer.
  Afterward, stuck matches and fixpoints pass in both directions; incorrect
  fields and eta for a plain inductive are rejected at `Qed`.
- The focused suite is `run-regressions.sh`: six checks here plus the preceding
  30 checks, sequentially under memory guards. All **36** pass under tag
  `eta-fallback-final`. This is not the full Rocq suite.
- 19 shell tests cover checkpoint creation/reuse, stage selection and explicit
  migration. Unknown history, altered proof input and corrupted artifacts are
  still rejected.
- The real continuation from `Prefix15M.vo` through **15,281,867** passes
  (`CheckLratRestore.eta-fallback.*`): 157,517 cumulative declarations, successful
  `Check` of the target, and atomic creation of `CheckLratRestore.vo`.
  Peak cgroup memory: 4,231,404 KiB (about 4.0 GiB). Both historical prefixes
  and the 15M seal still match their original hashes. The full continuation
  to EOF was not launched.

Diagnostic setup logs are retained: the first `Inspect` requested a nonexistent
accessor name, and the first `AccessEta` used an imported name shadowing
`Lean.eq`. Corrected versions run separately; these are not theorem failures.

## Resume from the saved 15M checkpoint

Use the same command:

```sh
bash work/uint32-not-repro/resume-cslib.sh
```

It verifies and reloads **the existing** `Prefix15M.vo`, then continues at
**15,001,016**. The worker pin is updated. The checkpoint, its original seal and
all proof inputs remain unchanged: `check-prefix15m.sh` recognizes that exact
historical seal and checks every entry except the explicitly changed worker
and two launch/check scripts. This does not disable Rocq's `.vo` digest checks.

One worker, 16 GiB hard cap, 15 GiB RSS limit, 3 GiB available-memory reserve,
no workload swap. Logs remain at:

```sh
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

For a bounded check from the saved prefix, stopping immediately after this
theorem, use `bash work/lrat-restore-repro/check-prefix15m-load.sh UNIQUE_TAG --through-target`.
It has a separate log and output module and does not overwrite either prefix
or the full continuation. Without `--through-target`, it only verifies a reload.

```text
previous worker: d9710716293105293cdbdd0d26d926d5015c90c5145c13d18943671f5423cc8f
patched worker:  16f0ef6d7027cf2e4734df1aa6f511f9cb6b22feb3a62a57b78fd01bcd8b4f0e
reduced export:  057356cbad1bbb9d05d0f2f361aa1888b6b6e170d43f5c7c030afc87ae6e1167
historical seal: 77e16b17b8c8bc0477074f2c4cf65a9ef2a7ec01b634c26f526aab96410f5279
```
