# Projected record casts: fresh bitvector-adder reproduction

The unchanged dependency-only export now passes from line 1 with the live
experimental kernel. This is a focused result, not a complete cslib pass.
The final rebuild, standalone controls, and all 44 compiler regressions passed.
The Python suite passed (185 tests, 2 skipped). The subsequent full-library
launch was refused by the memory guard; no full cslib worker is running.

## Failure and fix

The full line-1 run `work/cslib-from-start/20260908T132914665228Z` timed out
after 600 seconds at original export line 8,680,510:

```text
Std.Tactic.BVDecide.BVExpr.bitblast.blastAdd.go_denote_eq._unary
```

Comparing applications of the same `Ref.cast` beneath a field projection first
compared their arguments, including target AIGs containing recursive
`blastAdd.go` computations. The selected `gate` and `invert` fields simply
forward existing values: reducing the cast and projection discards those
target parameters. Computing them was unnecessary for the field equality.

The final change is only a conversion-order preference. For a transparent
constructor wrapper beneath a matching projection, it recognizes a selected
field that is a variable or a primitive-projection chain rooted in a variable.
It unfolds that forwarding wrapper before whole-argument congruence, and
prefers that side when only one side qualifies. Wrappers that **compute** their
selected field keep the previous congruence order. The guard requires typed
conversion and the existing dependency-heuristic option.

No equality rule, Lean proof, importer translation, or declaration-skipping
policy was changed. Ordinary kernel reduction and conversion still establish
the result. The work-budget, quotation-API, and source-alignment trials were
discarded; their saved candidate files and logs are historical experiments.
The final source is [conversion.forwarded-fields.ml](conversion.forwarded-fields.ml),
matching the live `kernel/conversion.ml`. CClosure trial APIs were removed.
`kernel-change.patch` records only this task's change against `conversion.ml.before`.

## Evidence

- [baseline-entries](baseline-entries/run.log) fails on the same `_unary`
  declaration in the fresh reduced export; peak cgroup memory was 505,304 KiB.
- [DiscardedParameters.v](DiscardedParameters.v) isolates the same problem with
  an indexed record cast and a costly discarded target. The
  [baseline](discarded-baseline/run.log) times out at its first `Timeout 5 Qed`
  (line 30). [forwarded-fields-controls](forwarded-fields-controls/guard.log)
  exits 0 and saves `DiscardedParameters.vo`, including both positive directions,
  changed-payload rejection, and rejection through a genuinely `Qed`-opaque cast.
- [forwarded-fields-fresh](forwarded-fields-fresh/run.log) checks all **426,817
  lines**, including `_unary` at 426,138 and the public theorem at 426,817:
  3,471 entries, strict error handling, no parsing-only mode, no skipped quotient,
  no lazy instantiation, and 60 seconds per declaration. The
  [guard](forwarded-fields-fresh/guard.log) exits 0; `Fresh.vo` is saved.
  Peak cgroup memory: **413,256 KiB**.

The final gate repeated the original export successfully after removing the
trial CClosure changes (414,000 KiB peak) and passed both new controls plus all
31 previous targeted checks and ten importer fixtures. See
[passed.json](forwarded-fields-final-regressions/passed.json) and
[the complete gate log](check-and-run-final.log). No historical Lean checkpoint
was loaded (`plan_sha256` is null).

Pending: a fresh 22.8-million-line cslib run. The attempted launch in
`work/cslib-from-start/20260908T182054551727Z` exited 75 before compiling:
18,791,900 KiB was available; the unchanged guard requires 19,922,944 KiB
(16 GiB budget plus 3 GiB reserve). Earlier checkpoint-based successes do not
substitute for this full run. When sufficient memory is available, restart
only the full run; there is no need to repeat the successful gate:

```sh
python3 scripts/run_cslib_from_start.py
```

Tested worker SHA-256:
`78cfbfb0660e84e0c62e110fd1e60b3262057b815f5f3deda10edf48fccb8ad7`.
Final `kernel/conversion.ml` SHA-256:
`0f68720f579a87fa4e84cbd77a799822dcb066f2d450095012ac1b15170fad57`.

## Input provenance

[export.sh](export.sh) exports the original public theorem `blastAdd.go_denote_eq`
and its dependency closure, including the generated `_unary` proof. There is no
replacement proof or compiled Lean prefix. [export.log](export.log) records:

- Lean **4.27.0-rc1**, commit `2fcce7258eeb6e324366bc25f9058293b04b7547`;
  lean4export **3.1.0**. Original cslib commit:
  `02e2a23eef42925cc87a5ce2ec76e9d07fdee267` (`cslib.stats.json`).
- `Target.ndjson` SHA-256:
  `55263ea31a062233282ee2836e7887957a5ad37d329f57ad964dbcf42269f9ea`.
- `Target.lean-export`: 426,817 lines, 10,349,481 bytes; SHA-256:
  `f27289936d1fb71ec93603013876615b3dbe46dff05d1c43e972b93991ce3e72`.

The exporter and converter hashes are pinned in `export.sh`. Matching Lean
source is in `_deps/lean4-src-4.27`; its kernel prioritizes projection reduction
against expensive definitions (`src/kernel/type_checker.cpp:881–899`). This
motivates the scheduling comparison, not a claim of identical kernel behavior.

## Reproduce

Run from the repository root, sequentially, with no competing guarded worker:

```sh
bash work/blastadd-unary-repro/rebuild.sh
bash work/blastadd-unary-repro/run.sh DiscardedParameters controls-NEW
bash work/blastadd-unary-repro/run.sh Fresh fresh-NEW
python3 work/blastadd-unary-repro/validate.py \
  --foundation work/blastadd-unary-repro/fresh-NEW/foundation/Lean.vo \
  --directory work/blastadd-unary-repro/regressions-NEW
```

`rebuild.sh` serially rebuilds the live kernel, matching plugin, and required
Stdlib artifacts under the shared guard; it does not select a saved candidate.
`run.sh` requires a new tag, compiles a fresh `Lean.v` foundation, and never
loads an old Lean checkpoint or changes the full-run `latest` pointer. Its
limits are 4 GiB cgroup memory, 3.75 GiB RSS, a 3 GiB system reserve, zero swap,
an 8 MiB stack, and a 600-second outer deadline. `validate.py` stages fresh
regression sources and dependency imports. The successful final gate is
`forwarded-fields-final-regressions/`; its log is `check-and-run-final.log`.

To repeat the gate and then launch full cslib only on success:

```sh
bash work/blastadd-unary-repro/check-and-run.sh review-NEW
```

This does not rebuild the kernel or enable the autonomous repair loop. The
full run starts at line 1, uses the existing 16 GiB memory guard, and updates
`work/cslib-from-start/latest`. Follow `Full.run.log` and `guard.log` there.

The export already exists. To regenerate in a clean reproduction location,
invoke `export.sh` through `work/run-memory-guarded.sh`; it refuses to overwrite
either saved export file. Preserve these artifacts and logs for comparison.
