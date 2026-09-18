# Constructor wrappers: `UInt32.toInt32_not`

The cslib continuation stopped at line **14,939,797** with a stack overflow,
below its memory limit. The original Lean theorem is:

```lean
theorem UInt32.toInt32_not (a : UInt32) :
    (~~~a).toInt32 = ~~~a.toInt32 := rfl
```

## Fix

Conversion kept `UInt32.toInt32` folded while comparing its record fields
through projections. The opposite side's argument also contained this wrapper;
unfolding that side eventually forced the recursive bitwise implementation.
The wrapper itself could have exposed its constructor immediately.

The kernel now unfolds transparent syntactic constructor wrappers before
trying record eta, in either direction. It inspects only lambda/application
heads, and only with application-only stacks. Other definitions and existing
eliminations retain their old path. The resulting terms still undergo ordinary
conversion; there is no new equality rule, arithmetic shortcut or library-name
special case. No importer or Lean proof changed.

Local branch: `fix/constructor-wrapper-conversion`, commit `33ee807ae0`, based
on `fix/compact-fueled-arguments`. The exact kernel delta is built in the live
experimental worktree. Not pushed; not a stock-Rocq or soundness result.

## Validation

- The unchanged theorem and dependencies export to 22,363 lines with Lean
  4.27.0-rc1. `Target.baseline.*` reproduces the stack overflow with an 8 MiB
  stack; `Target.trace.*` records the unfolding path.
- `Target.constructor-wrapper.*` passes with that same stack; declaration
  checking completes at 0.88 CPU seconds, including prefix loading.
- `Fresh.wrapper-final.*` imports all 469 entries from scratch. The five
  original UInt8/UInt16/UInt32/UInt64/USize complement theorems also pass.
- `ConstructorWrapper.baseline.*` times out at the first kernel check.
  `ConstructorWrapper.wrapper-final.*` passes in both directions and rejects
  an unequal field and genuinely opaque wrappers at `Qed`. Earlier control
  setup attempts incorrectly expected the `Opaque` command to impose kernel
  opacity; the final test uses a definition closed with `Qed` instead.
- All **30** selected kernel/importer checks in `run-regressions.sh` pass
  under tag `wrapper-final`, sequentially with memory guards. This includes
  the preceding HashMap, division, unit-projection, FinLoop and importer tests;
  it is not the complete Rocq test suite.
- `python3 -m unittest discover -s scripts/tests -p test_sealed_checkpoint.py`
  passes 14 tests of checkpoint reuse, input/artifact validation, failure,
  competing launchers and stage selection, without running Rocq.
- The small real checkpoint chain passes creation, verified reuse, continuation
  and fresh-process reload (`wrapper-seal-final`). Its first reload check needed
  an explicit import of the intermediate module to expose the checked name;
  the full-run reload driver includes the same correction.
- `../unit-projection-repro/check-prefix.sh constructor-wrapper` passes:
  the unchanged 11M checkpoint loads with the rebuilt kernel and a dependent
  module saves. Historical input hashes still match. This checks load
  compatibility, not rechecking every proof inside the old checkpoint.

## Checkpoint at 15M

Create and freshly reload the new checkpoint, then stop:

```sh
bash work/uint32-not-repro/resume-cslib.sh --checkpoint-only
```

This resumes the unchanged 11M checkpoint at **11,005,951**. It checks through
**15,001,015**, the declaration `Std.Tactic.BVDecide.BVPred.bitblast_Inv_of_Inv`,
then atomically saves `Prefix15M.vo` and verifies a fresh-process load.
The import ranges are end-exclusive; continuation begins at **15,001,016**.

After that succeeds, continue to EOF:

```sh
bash work/uint32-not-repro/resume-cslib.sh
```

The normal command also builds the 15M checkpoint first if it does not exist.
The old `work/unit-projection-repro/resume-cslib.sh` entry point delegates to
this launcher. Both use the same launcher lock and `latest` log location:

```sh
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

One worker; 16 GiB hard cap, 15 GiB RSS limit, 3 GiB available-memory reserve,
no workload swap. Each launch prints its systemd service and service-log path.

The old prefix and historical manifests are unchanged. The new checkpoint has
a separate seal recording its producer inputs and artifact digest. Reuse checks
both; an unsealed or changed file is refused, not silently reused or overwritten.
A later kernel migration needs an explicit compatibility review of that seal.

The 15M/full-library runs were **not launched during this fix**. The 15M
checkpoint is configured, not yet established. A small real checkpoint chain
can be exercised with `bash work/uint32-not-repro/run-sealing-test.sh UNIQUE_TAG`.

```text
previous worker: 00d7abf71ecd1070756e9258d23054f1a7cb95113a9b9f8ce3450e93f28a7912
patched worker:  d9710716293105293cdbdd0d26d926d5015c90c5145c13d18943671f5423cc8f
UIntNot export:  0c5cb5e04e2b1fc8b36efa5e41ac6948ceed90cb612358a2133d709a0a4576f0
Widths export:   15b56527b20a29cbf938d7891f22ce8397346e5841e0f9b8205d1f2cd63ee06e
```
