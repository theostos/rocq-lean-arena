# Bounded congruence: `UInt32.toUInt64_shiftLeft_of_lt`

The continuation failed at **16,372,304** with a stack overflow, well below
its memory limit. The original Lean theorem relates widening a 32-bit left
shift to a 64-bit shift followed by reduction modulo `2^32`.

## Cause and fix

Translation succeeds; kernel conversion fails. While comparing different
widths, congruence enters recursor branches and partially applied comparisons
over large naturals. Those branches would not be taken by evaluating the
original applications.

The experimental kernel now bounds this trial strategy to **256 nested,
uncached conversion calls**, then falls back to ordinary unfolding. Nested
comparisons share the counter and restore it on return. Only an unfoldable
definition can start this budget;
opaque and local heads retain unrestricted congruence. The peeled-application
probe also shares this mechanism. The limit concerns nesting depth, not total
work: long, shallow comparisons can still succeed by congruence.

This is not a timeout or a proof-checking limit. It does not bound every
reduction step. Exhaustion never accepts an equality. No importer, arithmetic
registration or Lean proof changed.

Local review branch: **`fix/bounded-congruence`**, based on
`fix/congruence-probe-scope`, commit **`1ff9ec82b3`**; not pushed.

## Reproduction and tests

- `export.sh` exports the unchanged theorem from `Init.Data.UInt.Bitwise`
  using Lean 4.27.0-rc1: 117,502 lines and 1,727 entries.
- `Target.baseline.*` reproduces the stack overflow with an 8 MiB stack.
  `Target.entries.*` identifies conversion call 217; `trace-detail` shows
  entry into unused modulus/recursor branches and partial `Nat.ble` comparison.
- `Target.depth-final.*` passes under the same 8 MiB stack.
- `Fresh.depth-final.*` imports all dependencies and the target from
  scratch. `Widths.depth-final.*` checks six original widening-shift
  theorems; `Reload.depth-final.*` loads the saved target.
- `BoundedCongruence.baseline.*` reproduces the overflow in pure Rocq.
  The final test also rejects wrong results and opaque unfoldings and accepts
  long comparisons under opaque and local heads.
- All **45** selected kernel/importer checks pass under tag **`depth-final`**,
  sequentially under memory guards. This includes all 40 preceding checks.
  The **19** checkpoint-runner unit tests also pass.
- The unchanged 15M checkpoint reloads and the dependent module saves with
  the final worker (`../lrat-restore-repro/Reload15M.bounded-congruence.*`).
  Peak cgroup memory is 1,978,212 KiB (about 1.9 GiB). Both historical prefixes
  and the 15M seal pass their hash checks before and after the reload.

Run the focused suite sequentially through the memory guard:

```sh
bash work/uint32-shift-repro/run-regressions.sh UNIQUE_TAG
python3 -m unittest discover -s scripts/tests -p test_sealed_checkpoint.py
```

The early parameter-ordering and prefix-only budget trials did not solve the
failure. The first general budget regressed on
`Nat.Linear.Poly.of_denote_eq_cancelAux`; excluding heads without an unfolding
fallback fixes that regression. Counting total work also slowed down
`Std.HashMap.unitOfList_cons`; the final depth limit preserves that earlier
fix. The logs retain these attempts.

These are tests of the combined experimental kernel, not stock Rocq, the
entire Rocq suite or a soundness certification.

## Resume

The worker pin is updated; neither saved prefix nor the historical 15M seal
is rewritten. The migration checker validates the original checkpoint and
all unchanged proof inputs. Loading an old checkpoint checks compatibility,
not all of the proofs already stored in it.

Use the same command to resume from the sealed 15M checkpoint:

```sh
bash work/uint32-not-repro/resume-cslib.sh
```

One worker, 16 GiB hard cap, 15 GiB RSS limit, 3 GiB available-memory reserve,
no workload swap. Logs:

```sh
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

The full continuation to EOF remains user-launched. This fix was checked on
fresh dependency-only imports, not by replaying the whole 15M–16.37M interval.

```text
previous worker: 107dd62ef1e299196f4941a1fdfafb445132dce75c19ac3840bdf2bcec98f49e
patched worker:  e690ad45a8bbc7b7e93aad63fa72e6a01126287e57c12b675c1f7d938a7ce6c3
target export:   b3d85c7c83c4e25142261853b69650994646d060a2e342d9898fae78d2212f0f
widths export:   114140383c96662457476bb11d277dd6e40ac782963431d090f0112680f787f4
historical seal: 77e16b17b8c8bc0477074f2c4cf65a9ef2a7ec01b634c26f526aab96410f5279
```
