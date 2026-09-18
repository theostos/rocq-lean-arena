# Source-preserving Boolean primitives: `Nat.beq.eq_def`

This repairs the declaration reported at full-export line **19,973,193**.
The unchanged theorem's dependency-only export and baseline failure are in
`../nat-beq-eq-def-repro/`. This follow-up uses the authorization for a fresh
representation generation; it does not reuse that reproduction's old `.vo`
files or launch a full-library continuation.

## Cause and implementation

Lean's `Nat.beq` body uses `Nat.brecOn`, with a recursive history represented
by products. The old importer replaced it with a foundation fixpoint returning
`Bool` directly. These have matching numerical behavior but different open
terms: the original `Nat.beq.eq_def` proof requires a projection of the source
recursor to convert to the source function at a variable argument.

The change is in `declare_def` in the live importer's `src/lean.ml`:

- Retain and typecheck the exported bodies for the existing primitive kinds
  `Beq`, `Ble`, `Blt` and `Nat_decEq` instead of returning their foundation
  replacements. The strict-comparison and equality-decision wrappers must
  refer to the retained comparisons too.
- Register each imported `Beq`/`Ble` constant through the existing
  `Global.register_peano_nat_beq`/`Global.register_peano_nat_ble` functions.
  Their kernel validators check all defining equations after removing compact
  Peano registrations and the conversion oracle from the validation environment.
  Invalid or opaque functions are rejected. This reuses the existing generic
  evaluator and validator; no kernel implementation change is needed.

The only name dispatch is the existing primitive-operation table. No library
theorem name appears in the implementation. The original library proofs are
imported without edits or replacement proofs. Other predeclaration kinds
retain their existing behavior; this is not a claim that all replacements
have now been audited.

`lean.ml.before` captures the source before this repair, including the user's
existing changes. Compare it with the live source to review this repair alone.
No foundation or kernel source was changed. The importer plugin was rebuilt
against the live experimental kernel with OCaml 4.14.2 / `rocq93_native`.

## Focused validation

```sh
bash work/nat-bool-source-repro/build.sh
bash work/nat-bool-source-repro/run-focused.sh UNIQUE_TAG
```

The build has a 300-second timeout and uses `work/run-memory-guarded.sh`.
Each focused check uses the existing atomic runner and memory guard: 180-second
process timeout, 2 GiB hard memory, 1.75 GiB RSS, 6 GiB available-memory reserve,
no workload swap, 8 MiB stack. The owner service is inherited.

Results with the final importer (`source-v2`):

- `Fresh`: all 22 entries, including the unchanged target proof, check and save.
- `Prefix`, `Target`: dependencies check and save, then the target checks after
  loading that newly generated dependency checkpoint in a separate process.
- `Reload`: the fresh target module loads successfully.
- `Adjacent`: 84 entries check, including the original `Nat.beq_refl`,
  `Nat.beq_eq`, `Nat.ble_eq` and `Nat.blt_eq` proofs. This is a separate export
  from `Init.Data.Nat.Basic`, with 3,565 lines / 66,880 bytes.
- `BooleanRegistration`: source and foundation implementations remain distinct
  as open functions; a transparent alias passes generic registration; equality
  and inequality around `2^64` compute within five seconds; a wrong result,
  four definitions violating different recurrence equations, and an opaque
  implementation are all rejected.

The first implementation retained only the two comparison primitives.
`Adjacent.source-v1` then rejected `Nat.blt_eq` because its foundation wrapper
still used the old comparison. Retaining the dependent wrappers resolves that
representation inconsistency. The first Boolean control run selected an
unavailable aggregate stdlib module; it now uses the available `NArith.BinNat`.
These initial logs are retained separately from passing results.

`ComparisonControls.source-v2` also passes: large less-than-or-equal and strict
comparisons, a wrong result, invalid registration and the strict wrapper's
open-argument unfolding. All seven focused fixtures passed with the final
plugin. The maximum focused-test cgroup peak was 200,076 KiB.

## Broader gate: protected staging blocker

```sh
python3 scripts/checkpoint_generation.py \
  --foundation /home/theo/Documents/github/rocq-lean-typechecker/work/int32-tdiv-repro/foundation/Lean.vo \
  --directory /home/theo/Documents/github/rocq-lean-typechecker/work/nat-bool-source-repro/regressions-source-v2
```

The unmodified gate ran to completion with **exit 65** after **34 passing
stages**. All selected shift, list-insertion, LRAT, complement and minimum
division checks passed, as did the HashMap prefix, target, reload and fresh
import. It then failed before checking `DirectDependency.v`:

```text
Can't find file
../../_worktrees/rocq/compact-peano-view/test-suite/success/direct_unfolding_dependency.v.
```

The existing fixture contains exactly that relative `Load` command. The
source exists in the live kernel worktree. However, `validate` copies the
wrapper into `<regression-directory>/work/hashmap-unit-cons-repro/` without
staging the source at `<regression-directory>/_worktrees/...`. This is a
missing-input error, not a proof or registration rejection. See
`regressions-source-v2.log` and the staged
`work/hashmap-unit-cons-repro/DirectDependency.{run,guard}.log`.

The repair returns **blocked** because the protected gate needs its source
staging corrected. Neither `scripts/checkpoint_generation.py` nor the existing
fixture was changed, and no substitute input or bypass was installed. The
remaining gate stages and its final unit-test invocation were not reached;
there is no `passed.json`. The tested importer repair remains installed for
review. No full-library process was launched or restarted.

## Representation and checkpoint action

**Request `checkpoint_action="restart"`.** The importer now stores the actual
source functions and their registrations. Existing checkpoints contain the old
substitutions and must not be reused for this representation. The supervisor
owns the new manifest, line-1 checking chain and all full compilation.

Keep the existing foundation:
`/home/theo/Documents/github/rocq-lean-typechecker/work/int32-tdiv-repro/foundation/Lean.vo`.
Neither the legacy worker pin nor historical manifests/seals were changed.
The checkpoint directory had no `progress.json` when inspected.

```text
worker (unchanged):     e690ad45a8bbc7b7e93aad63fa72e6a01126287e57c12b675c1f7d938a7ce6c3
foundation (unchanged): de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b
old importer:          93f048367978e9d36bc8f79831eea0ce3b4dac5104297c843ffe95bfa13aec07
tested importer:       6304d147f1085e72463e7efc1d9bd9c2ff5920ddd95403102d2ca6f791a13bb1
target export:         3fcc3abffb5bf880b82396d9fcc4608e91e73f6911b640e594e0f3aa1743e9b8
adjacent export:       84cfa8de27197a69cc0e8f39760e05b738c19924bd9409da3752b227cee757e4
```

These checks use the combined experimental kernel. They are neither a
full-library checking result nor a soundness certification.
