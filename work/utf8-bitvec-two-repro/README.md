# Direct witnesses for one-sided dependency preferences

Reported declaration (full-export line **697,462**):

```text
_private.Init.Data.String.Decode0.String.toBitVec_getElem_utf8EncodeChar_zero_of_utf8Size_eq_two
```

`Utf8BitVec.lean-export` preserves the original Lean theorem and its dependencies:
146,567 lines / 3,308,267 bytes, exported from `Init.Data.String.Decode` with
Lean 4.27.0-rc1. The target is at line 146,567. `Prefix.baseline` checks and
saves the 1,950 dependency entries; `Target.baseline` reproduces the timeout
after loading that dependency checkpoint. No full compilation was repeated.

## Cause and repair

Translation and universe processing finish in about 25 milliseconds. The
timeout occurs in kernel conversion call 229, comparing equalities involving
the first byte's bitvector and a list lookup. The list recursor can expose the
same byte expression. However, the other side's bitwise arithmetic has a
transitive dependency on the same general recursors. When the reverse closure
probe exceeds its budget or encounters an unsupported form, the previous
one-sided preference chooses that transitive dependency and unfolds arithmetic
instead. It then makes millions of successful comparisons inside the expanded
arithmetic. `Target.trace` exceeds eight million trace steps before the
30-second line timeout.

The final change is confined to `kernel/conversion.ml` in the live kernel:

- Add a `transitive` option to the existing bounded dependency probe. With
  `transitive=false`, only an actual constant occurrence in the inspected
  process is a witness; the environment's transitive dependency query is not
  used. Existing substitution traversal, update-alias checking and the
  1,024-visit budget are preserved.
- If one probe is positive and the reverse probe is unknown, repeat the
  positive probe in this direct-occurrence mode before preferring that side.
  Otherwise retain the ordinary unfolding strategy. Comparisons for which
  both probes return known results are unchanged.

This selects an unfolding direction only. It does not accept an equality or
alter a checking rule. There are no declaration-name cases, new axioms, edited
library proofs or representation changes. The importer and foundation are
unchanged. `conversion.ml.before` includes all pre-existing worktree edits,
and `rocqworker.baseline.exe` preserves the exact starting worker.

The initial constructor-elimination preferences (`constructor-trace` and
`iota-trace`) still timed out and were removed. The final direct-witness repair
passes `Target.direct-trace`: conversion call 229 finishes before trace step
128. The target checks using the dependency checkpoint saved by the baseline
worker.

## Reproduction commands

```sh
ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152 \
ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0 \
bash work/run-memory-guarded.sh \
  timeout --signal=TERM --kill-after=5s 180 \
  bash work/utf8-bitvec-two-repro/export.sh

bash work/utf8-bitvec-two-repro/run.sh Prefix baseline
ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES=1 LEAN_IMPORT_DECLARE_TRACE_LINE=146567 \
  bash work/utf8-bitvec-two-repro/run.sh Target baseline
ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL=229 \
  bash work/utf8-bitvec-two-repro/run.sh Target trace

bash work/utf8-bitvec-two-repro/build.sh
ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL=229 \
  bash work/utf8-bitvec-two-repro/run.sh Target direct-trace
bash work/utf8-bitvec-two-repro/run-focused.sh final
```

Baseline commands preceded the repair; tags preserve their logs. Set
`ROCQ_TEST_BASELINE=1` to use the saved baseline worker without replacing the
live worker. Export outputs and run tags must be new.

`Adjacent.lean-export` is exported with the same guarded export command using:

```text
Adjacent
_private.Init.Data.String.Decode.0.String.toBitVec_getElem_utf8EncodeChar_one_of_utf8Size_eq_two
_private.Init.Data.String.Decode.0.String.toBitVec_getElem_utf8EncodeChar_zero_of_utf8Size_eq_three
```

This is one invocation, with the three lines above supplied as three arguments.
The adjacent export has 147,458 lines / 3,330,145 bytes.

The build uses one dune job under the existing memory guard with a 300-second
timeout. Repros use the existing atomic runner, 2 GiB hard memory, 1.75 GiB RSS,
6 GiB available-memory reserve, no workload swap, 8 MiB stack, 180-second
process timeout and 30-second import-line timeout. The owner service is
inherited. No limits or guard checks are weakened.

## Validation

The previous UTF-8 repair's six focused fixtures pass unchanged:

```sh
bash work/utf8-encode-eq-def-repro/run-focused.sh bitvec-direct
```

See `prior-focused.log` and the original directory's `*.bitvec-direct.*.log`.
This covers the original `String.utf8EncodeChar.eq_def`, its length and fast
encoder equivalence theorems, saved module reloads, substituted closures,
dependent lambda domains and three negative controls.

The new `TransitiveDependency` fixture checks wrapper equalities in both
directions, with an explicit unused branch, and requires kernel rejection of
an unequal result and an opaque body. It is a control fixture and also passes
with the baseline worker; the unchanged exported target is the performance
regression. `exact_no_check` defers tactic elaboration only: the positive
proofs and negative attempts undergo kernel checking at `Qed`. Failed
negative attempts are aborted without adding declarations.

All **six new focused fixtures pass** (`focused.final.log`):

- `Fresh`: all 1,951 entries, including the unchanged target theorem.
- `Prefix` / `Target`: fresh dependency checking and save, followed by target
  checking after reload in a separate process.
- `Adjacent`: 1,958 entries, including the original second-byte theorem for
  size two and first-byte theorem for size three.
- `TransitiveDependency`: both equality directions and both required kernel
  rejections.
- `Reload`: the newly saved target and adjacent modules load successfully.

Peak cgroup memory was **288,168 KiB** for the new focused checks and
**307,448 KiB** for the final guarded build. The entire new control fixture
finished in less than one second, so its required failures were not timeouts.
Shell syntax checks and the live kernel's `git diff --check` also pass.

Run the unchanged broader gate without creating a checkpoint generation:

```sh
python3 scripts/checkpoint_generation.py \
  --foundation /home/theo/Documents/github/rocq-lean-typechecker/work/cslib-loop/20260908T055032055969/validation-retry/generation/foundation/Lean.vo \
  --directory /home/theo/Documents/github/rocq-lean-typechecker/work/utf8-bitvec-two-repro/regressions-direct
```

The broader gate completed with exit 0: **58 compiler stages passed**, followed
by **170 unit tests, OK (two existing unit-test skips)**. See
`regressions-direct.log` and `regressions-direct/passed.json`. All compiler
guards completed with status 0; the largest peak was **306,220 KiB**. The
gate's original-input and toolchain digest checks passed, and its recorded
worker digest matches the final worker below. Messages about full continuations
and Mathlib in this log are isolated unit-test output, not actual library runs.

The new control fixture also passed again under tag `comment-final` after its
comment was clarified. No implementation change followed the final build.

## Compatibility and scope

Request **`checkpoint_action="reuse"`**, **`foundation=""`**. This patch changes
only unfolding strategy. The active foundation remains:

```text
/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-loop/20260908T055032055969/validation-retry/generation/foundation/Lean.vo
```

No `progress.json` was present in the active or original cslib checkpoint
directory when inspected. The supervisor owns all full compilation, reload
gates, checkpoint saves and waiting. Historical checkpoints, manifests, seals,
plans and existing regression sources are preserved.

Only after all tests passed, the current worker digest in
`work/unit-projection-repro/check-toolchain.sh` was updated. Its other digest
checks and the historical producer manifests are unchanged. The importer and
foundation hashes were verified again against their starting values.

These are scoped tests of the experimental kernel, not a full cslib result or
a soundness result. A checkpoint reload checks compatibility, not all stored
proofs.

```text
baseline worker: c63dba1923052ffb2beafba1b7496a489a6cb3fae59b212b9eb841bd2287d5a8
patched worker:  d338d5ec581d16f710e5ff43f7d1d8a38206e84a6c40bc3cfd16bccc007a0248
importer:        6304d147f1085e72463e7efc1d9bd9c2ff5920ddd95403102d2ca6f791a13bb1
foundation:      de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b
target export:   3e139c2c373b6ea471b6f9dced978f0cbb4dd8e567df534a19a09cf0ecb1c2f9
adjacent export: 393c305e327d76c704fc9cce03a1cf62045ab8ef97109e4c8a600b5bf030ceed
```
