# Binder scope: `List.insertIdx_eraseIdx_of_le`

The cslib continuation failed at **15,367,062** with `Not_found`.
This is a bug in our experimental kernel's application-congruence probe,
not a missing Lean declaration or a resource limit.

## Cause and fix

The probe copied closures through ordinary terms and rebuilt them with
`inject`, which assumes no locally bound variables. Under binders this changed
bound `FRel` variables into external `RelKey` references. The backtrace reaches
`irr_flex` and `Environ.lookup_rel`, looking outside the available environment.

Apply each side's lift, then rebuild with the current binder depth and compare
with identity lifts. This preserves scope without suppressing the exception,
changing conversion rules or rewriting any library proof. Only
`kernel/conversion.ml` changes; the importer is unchanged.

Review branch: **`fix/congruence-probe-scope`**, based on
`fix/stuck-record-eta`, commit **`42bb6c4a0b`**. Local only. The preceding four
`fix/` branches were published earlier; their historical snapshots are unchanged.

## Evidence

- `export.sh` exports the original theorem and dependencies from
  `Init.Data.List.Nat.InsertIdx`, using Lean 4.27.0-rc1: 4,380 lines, 75 entries.
- `Target.baseline.*` reproduces the anomaly; translation succeeds and kernel
  declaration checking fails. `Target.entries.*` identifies conversion call 219.
- `Target.scoped-probe.*` passes with the rebuilt worker.
- `ProbeScope.baseline-final.*` reproduces the same anomaly in pure Rocq.
  The patched controls cover lambdas, eta lifts, outer relatives, fixpoints,
  SProp binders and products. Distinct-variable equalities are rejected at `Qed`.
- All **40** selected checks in `run-regressions.sh` pass under tag
  `scoped-probe-final`, sequentially with memory guards. This includes a fresh
  import and reload, and all 36 preceding regression checks.
- **19** checkpoint-runner unit tests pass. There is no `.vo` digest bypass.
- The real continuation from `Prefix15M` through **15,367,062** passes
  (`CheckListInsertErase.scoped-probe.*`): 158,055 cumulative entries,
  successful `Check` of the target, and atomic creation of
  `CheckListInsertErase.vo`. Peak cgroup memory: 4,231,692 KiB (about 4.0 GiB).
  Both saved prefixes and the original 15M seal pass their hash checks before
  and after the run. The full EOF pass was not launched.

Early `ProbeScope.baseline`/`scoped-probe` logs record a missing numeric-notation
import in the test setup. Zero and decoder variants did not reproduce this
probe path; `baseline-final` is the final, constructor-based reproduction.

These results concern the combined experimental kernel, not stock Rocq, the
full Rocq suite or a soundness certification.

## Saved checkpoint and continuation

The worker pin is updated. The existing 15M checkpoint and its historical
seal are not rewritten. The explicit migration checker still checks the
checkpoint artifact and all unchanged proof inputs.
Loading an old checkpoint checks compatibility; it does not recheck all of
the proof bodies already stored in that checkpoint.

The bounded checkpoint test is:

```sh
bash work/list-insert-erase-repro/check-prefix15m.sh UNIQUE_TAG
```

It reloads `Prefix15M`, checks lines **15,001,016–15,367,062**, and saves a
separate `CheckListInsertErase.vo`. It does not replace either saved prefix
or launch the full EOF pass. Its limit is 12 GiB with a 6 GiB available-memory
reserve and one worker. Results are in `CheckListInsertErase.UNIQUE_TAG.*.log`.

To resume the full experiment yourself, use the same command:

```sh
bash work/uint32-not-repro/resume-cslib.sh
```

It reuses the sealed 15M checkpoint and continues to EOF: one worker, 16 GiB
hard cap, 15 GiB RSS limit, 3 GiB available-memory reserve, no workload swap.

```sh
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

```text
previous worker: 16f0ef6d7027cf2e4734df1aa6f511f9cb6b22feb3a62a57b78fd01bcd8b4f0e
patched worker:  107dd62ef1e299196f4941a1fdfafb445132dce75c19ac3840bdf2bcec98f49e
reduced export:  6a90191cfedac92416cbf050c4c966226e6dde8f7b5fae6d260ed60e41a933c0
historical seal: 77e16b17b8c8bc0477074f2c4cf65a9ef2a7ec01b634c26f526aab96410f5279
```
