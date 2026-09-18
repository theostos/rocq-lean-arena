# `Nat.beq.eq_def`: blocked by predeclared representation

The full checking attempt reported this declaration at line **19,973,193**.
A fresh dependency-only export reproduces the same illegal application at
line **1,127**, using the unchanged live worker, importer and foundation.
The original Lean theorem is exported from `Init.Data.Nat.Basic`; its proof
has not been translated by hand, replaced, edited or admitted.

## Cause

The exported `Nat.beq` body (NDJSON expression 333) has two lambda binders
and application head `Nat.brecOn`. The importer instead maps this declaration
to the predeclared `Lean.Nat_beq`:

- `_worktrees/rocq-lean-import/compact-peano-importer-current/src/lean.ml`:
  `get_predeclared_def_any` selects `Beq`, and `declare_def` returns the
  registered constant without translating the exported body.
- `src/Lean.v` in that worktree: `Nat_beq` is a direct structural fixpoint
  returning `Bool`.
- `Inspect.baseline.run.log` prints the actual imported recursors and the
  foundation fixpoint. `Nat_brecOn_go` recurses over pairs containing the
  result and recursive history; `Nat_brecOn` projects the result.

In the original proof's successor/successor branch, `r0` is a **local let**
bound to the history projection of `Nat_brecOn_go ... (Nat_succ n) ...`.
The failed reflexivity application requires `fst r0 m` to convert to
`Lean.Nat_beq n m`. Reducing the history gives a projection of the imported
recursor at the open variable `n`. The foundation side is a different
fixpoint at that variable. Their equal numerical behavior does not make
these open terms definitionally identical. This is a mismatch between the
source definition and its replacement, not a large-number resource failure.

`Fresh.body.run.log` contains the translated original proof, including the
let value, collected with the existing diagnostic option
`LEAN_IMPORT_DUMP_FAILED_DEF=Nat.beq.eq_def`. No diagnostic changes checking
or the exported theorem.

## Why this repair returns blocked

A source-preserving repair must address the generic predeclaration policy:
preserve imported bodies when a replacement does not preserve definitional
equality, and validate any accelerated representation against those bodies.
Replacing the proof or teaching conversion to accept this particular
declaration is not an acceptable repair.

Changing that policy or the foundation changes the representation already
stored in the existing checkpoints. Both the original input manifest and
`Prefix15M.seal/inputs.sha256` pin the importer and foundation below. The
current migration checker permits the specified worker migration, not a
changed importer/foundation. Merely loading a checkpoint cannot rebuild its
stored terms with a different representation.

This needs a checkpoint/rechecking decision outside the authorized repair
phase. No candidate production patch was installed. No kernel, importer,
foundation, digest check, migration checker, checkpoint, seal, full-pass
source, supervisor script or existing regression suite was modified. No full
compilation or checkpoint continuation was launched. The checkpoint directory
had a plan and generated sources but no `progress.json` when inspected.

## Reproduction and results

All exporter/checker processes ran sequentially under the existing memory
guard. Checker runs also used `run-checkpoint-atomic.sh`: 2 GiB hard memory,
1.75 GiB RSS, 6 GiB available reserve, no workload swap and an 8 MiB stack.
`ROCQ_MEMORY_OWNER_SERVICE` was inherited.

Run the export once in a directory without existing export outputs:

```sh
ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152 \
  ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0 \
  bash work/run-memory-guarded.sh \
  bash work/nat-beq-eq-def-repro/export.sh
```

Result: **exit 0**, 1,127 lines / 18,696 bytes, peak 319,168 KiB.
The exporter is Lean 4.27.0-rc1, followed by the existing streaming
NDJSON-to-lean-export converter.

Use unique tags on subsequent runs:

```sh
bash work/nat-beq-eq-def-repro/run.sh Fresh baseline
bash work/nat-beq-eq-def-repro/run.sh Prefix complete-expressions
bash work/nat-beq-eq-def-repro/run.sh Target complete-expressions
bash work/nat-beq-eq-def-repro/run.sh Inspect baseline
```

- `Fresh.baseline`: **exit 1**, original illegal application at line 1,127;
  peak 160,192 KiB. No target `.vo` was promoted.
- `Prefix.complete-expressions`: **exit 0**, all 21 dependency entries
  checked and saved. The upper bound **1,127 is exclusive**.
- `Target.complete-expressions`: **exit 1**, the same illegal application
  after reloading the dependency checkpoint; no target `.vo` was promoted.
- `Inspect.baseline`: **exit 0**, fresh-process dependency load and printed
  definitions; peak 158,420 KiB.
- `Fresh.body`: **exit 1**, same failure with the original translated proof
  printed by the existing diagnostic hook.

The first `Prefix.baseline` stopped at 1,126, excluding an expression needed
at 1,127; its `Target.baseline` therefore reported a parser `Not_found`.
The corrected `complete-expressions` runs include every prerequisite
expression and reproduce the reported type error. Those initial logs are
retained as evidence, not counted as the target reproduction.

No fix is claimed, so no rebuilt worker digest or passing post-fix regression
suite is reported. This evidence concerns the experimental Rocq kernel;
it is not a full-library result or a soundness result.

## Unchanged toolchain and exported input

```text
worker:     e690ad45a8bbc7b7e93aad63fa72e6a01126287e57c12b675c1f7d938a7ce6c3
importer:   93f048367978e9d36bc8f79831eea0ce3b4dac5104297c843ffe95bfa13aec07
foundation: de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b
export:     3fcc3abffb5bf880b82396d9fcc4608e91e73f6911b640e594e0f3aa1743e9b8
```
