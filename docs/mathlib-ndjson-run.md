# Monitored Mathlib NDJSON run

Lean 4.29 reference export, direct NDJSON importer, existing custom kernel.
Fresh chain beginning at line 1, checkpoints every 1,000,000 NDJSON lines.
Each checkpoint is atomically saved, hash-sealed, and reloaded in a fresh process.

```sh
python3 scripts/mathlib_ndjson_loop.py status
watch -n 15 python3 scripts/mathlib_ndjson_loop.py status
```

Status reports the active log, declaration, memory use and last validated checkpoint.
The background monitor runs without a model. After 60 seconds without a new
declaration it requests a native stack, then at most two more at 120-second
intervals. GDB also captures the stack when the line timeout fires; the timeout
signal is then delivered normally. Snapshot signals do not reach Rocq.

The old failure is `ContDiffAt.real_of_complex`, NDJSON line 4,855,906
(legacy line 4,855,902). Declaration-phase tracing is enabled there.
Checkpoint reloads change module/cache context, so passing that target is not
by itself evidence that the original uninterrupted-run timeout is fixed.

Resume after the background service has stopped:

```sh
bash work/mathlib-mul-fin-two-repro/resume.sh
```

The helper pins the kernel with the compact transitive-dependency cache,
wrapped-unit conversion, unit-type alias/projection repairs, and the projected
constant-dictionary repair, and the erased-proof congruence-probe fallback.
It requires the latest regressions, original-order 17M-to-17.65M replay and
fresh-reload records.
See the [erased-proof repair](../work/mathlib-mul-fin-two-repro/README.md),
[projected-constant repair](../work/mathlib-proj-app-repro/README.md),
[unit-type alias repair](../work/mathlib-punit-colimit-repro/README.md),
[wrapped-unit repair](../work/mathlib-punit-ext-repro/README.md), and the
earlier [11M memory repair](../work/mathlib-11m-investigation/README.md).
It resumes from the latest validated checkpoint (17M at the time of this repair).

The recorded timeout override originally began after the validated 4M checkpoint.
Earlier sources and seals are unchanged; subsequent sources use 1,800 seconds
per input declaration, including its on-demand dependencies. The override and
its runner are included in subsequent checkpoint seals.

The importer, kernel and supporting inputs must still match the saved seals.
The run keeps the single-worker, 16 GiB/no-swap memory guard and disk-space
checks. It pauses on failure; there are no automatic model repairs or deletions.

Validation: the native debugger and checkpoint/reload chain passed the Nat.beq
reproduction in three chunks, including interrupt-and-continue stack captures.
