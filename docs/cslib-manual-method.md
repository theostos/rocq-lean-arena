# cslib: manual, fresh checking

The autonomous cslib and queued Mathlib supervisors are stopped. Their `start`
and `worker` commands are disabled. Old checkpoints and logs are retained as
historical evidence, not inputs to new full runs.

## Run and watch

From the arena root:

```sh
python3 scripts/run_cslib_from_start.py --dry-run
python3 scripts/run_cslib_from_start.py
```

In another terminal:

```sh
tail -n 5 -F work/cslib-from-start/latest/Full.run.log work/cslib-from-start/latest/guard.log
```

Each invocation creates a new directory, rebuilds the Rocq `Lean.v` foundation,
and imports the complete Lean export from line 1 through EOF in one process.
It does not load a prefix, resume a checkpoint, retry, call a model or start
Mathlib. Compilation stops on the first error or timeout. A final `Full.vo`
is an output only; later invocations do not reuse it.

The existing live experimental kernel and importer are used, not the new
`submit/*` review stack. Their built artifacts must already exist. The runner
records their identities and dirty-source status; it does not rebuild or
silently deploy kernel/plugin changes. Existing Rocq Corelib/Stdlib files are
still prerequisites, not imported Lean checkpoints.

One memory guard covers the run: 16 GiB hard limit, 15 GiB RSS limit,
3 GiB available-memory reserve, no workload swap. It refuses competing Rocq
workers or insufficient memory. Memory checks are local shell work, not model
calls. Monitor manually; Ctrl-C stops the foreground run. Logs and the final
status remain in its directory. Do not modify the selected toolchain while it
is running.

`Done!` in the importer log is not by itself the final compiler result: wait
for the runner's successful exit and `result.json`. Saving the final artifact
can still fail. A failed or interrupted full run must start over.

Launcher validation (2026-09-08): policy/runner unit tests, a fresh 17-line
import, and guarded Ctrl-C cancellation passed. No full cslib run was launched
as part of this workflow change.

## How to investigate the next failure

1. Preserve the failing declaration and extract its dependencies. Check that
   small export from line 1 too; do not reuse a compiled Lean prefix.
2. Read the corresponding **Lean kernel** path, then compare bounded Lean/Rocq
   traces: heads, original/applied hints, projection steps and congruence attempts.
3. Test one generic change at the first relevant scheduling difference. Keep
   the translation and semantic extensions fixed during the A/B comparison.
4. Run the reproduction, adjacent cases and negative controls from scratch.
   Then the user launches another complete cslib run from line 1.

No manually rewritten library proofs, skipped declarations or weaker checking.
A dependency-only pass is diagnostic evidence, not a replacement for step 4.

## Lean source reference and first experiment

The export metadata pins **Lean 4.27.0-rc1**, commit
`2fcce7258eeb6e324366bc25f9058293b04b7547`. The matching local tree is
`_deps/lean4-src-4.27`; newer local Lean trees are not this experiment's reference.

Lean first uses cheap reduction, preserving opportunities to compare record
producers before forcing their fields. Lazy delta reduction tries same-definition
argument congruence, and can reduce a projection before unfolding an expensive
definition on the opposite side. See
[type_checker.cpp](https://github.com/leanprover/lean4/blob/2fcce7258eeb6e324366bc25f9058293b04b7547/src/kernel/type_checker.cpp#L875).

Definition hints order abbreviations first, larger regular heights next, and
opaque-hinted definitions last. Equal hints unfold both sides after applicable
congruence attempts. See
[declaration.cpp](https://github.com/leanprover/lean4/blob/2fcce7258eeb6e324366bc25f9058293b04b7547/src/kernel/declaration.cpp#L24).
An opaque hint is not a genuinely opaque proof body.

Our importer additionally promotes some projection-headed definitions to
`Expand` and delays some power definitions. Our kernel uses bounded dependency
probes and staged retries. These are not a direct port of Lean's schedule.
Relevant local entry points are `src/lean.ml` (`set_regular`) in the live
importer and `kernel/conversion.ml` in the live kernel.

The first experiment reproduced `Int8.toBitVec_not` (full-export line 3,842,943)
from its original dependency closure. Our experimental early record-eta path
kept `Int8.toBitVec` folded and descended into bitwise arithmetic. Trying delta
first, with the original eta fallback retained, matches the priority in Lean
and upstream Rocq. The original declaration then checks in about 17 ms rather
than exceeding 30 seconds. No importer or reduction-rule change was needed.
See `work/int8-conversion-repro/README.md` for reproduction and validation.
This fixes a measured blocker; it does not establish a full cslib pass.

Ordering existing reductions is separate from adding conversion rules such as
unit eta, compact-arithmetic machinery, or changing caches. Rocq's universes,
relevance and local contexts must remain respected. Following Lean's source
provides a better-specified experiment, not a soundness or performance guarantee.
