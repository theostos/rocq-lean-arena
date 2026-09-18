# Cslib checking: review map

The importer branch list below has been superseded by the
[current compatibility list and cleanup](importer-patches.md). The kernel
and arena sections retain their separate history.

The aim is to check the original cslib proofs in Rocq, by fixing the importer
generically, not rewriting library proofs.

```text
Lean library → Lean Kernel Arena NDJSON → lean-export → rocq-lean-import → Rocq
```

The current experiment uses a **modified Rocq kernel**. A complete cslib check
has not yet been established. The input has 22,828,731 lines and includes Lean,
Std, Batteries and Mathlib dependencies; several failures below are in those
dependencies, not cslib itself.

## How to review

Use each topic's stated review base. The current importer topics and copy-ready
PR text are in [the importer patch list](importer-patches.md). Their review notes
are kept on a separate documentation branch, not in each implementation commit.
The kernel and arena tables below describe their earlier review stacks.

For example, in the importer clone:

```sh
git fetch fork
git diff fork/submit/mutual-inductives...fork/submit/nested-recursors
git worktree add ../review-nested fork/submit/nested-recursors
```

Use a separate worktree. Do not switch or rebuild a checkout used by a running
experiment.

## Importer

Use [the current importer patch list](importer-patches.md) for the compatibility
fixes, optional performance work, current branch names and recovery instructions.
The old `review/*` and superseded implementation branches have been archived;
the retained `submit/*` stack has been built and tested on matching runtimes.

PR #70 remains open. Its historical `Int64.toInt_minValue` justification was
misattributed; see [the reproduced error and actual fix](pr70-universe-reproduction.md).
`submit/dependent-projections` is the standalone candidate, directly on upstream.
#70 is absent from every other submission topic and both importer integrations.

## Rocq kernel

Repository: [theostos/rocq](https://github.com/theostos/rocq).
Stack base: `f756383` (Rocq 9.3 development baseline).

| Topic diff | What to inspect / motivating case |
|---|---|
| [dependency-cache](https://github.com/theostos/rocq/compare/f756383...review/dependency-cache) | Direct dependency edges and bounded reachability answers; avoid retaining transitive closures during cslib checking. |
| [term-sharing](https://github.com/theostos/rocq/compare/review/dependency-cache...review/term-sharing) | Preserve physical DAG sharing in hash-consing and universe traversals. |
| [reduction-registrations](https://github.com/theostos/rocq/compare/review/term-sharing...review/reduction-registrations) | Validate Nat operations and eligible unit shapes; persist/substitute/recheck registrations. This is the common registration layer, before evaluation and unit eta. |
| [compact-peano](https://github.com/theostos/rocq/compare/review/reduction-registrations...review/compact-peano) | Compact internal Peano evaluation, with a constructor view for elimination. Read-only substitution inspection avoids copying/forcing closures (`Int32.ofInt_tdiv`). |
| [unit-eta](https://github.com/theostos/rocq/compare/review/compact-peano...review/unit-eta) | Unit conversion, supported projections and record-eta interaction. `LawfulMonadStateOf.modify_eq`; lazy projection-parameter substitution fixes the `LinearMap.exists_ne_zero_of_sSup_eq` assertion. |
| [conversion-strategies](https://github.com/theostos/rocq/compare/review/unit-eta...review/conversion-strategies) | Dependency/constructor ordering, projection congruence, relevance masks and successful-conversion caches. Cases: `Int32.toBitVec_not`, `Std.DHashMap.Internal.Raw₀.Const.insertManyIfNewUnit_cons`, `Lean.Widget.MsgEmbed._sizeOf_2_eq`. Still a substantial experimental patch. |
| [kernel-diagnostics](https://github.com/theostos/rocq/compare/review/conversion-strategies...review/kernel-diagnostics) | Remaining diagnostics. Includes an opt-in `.vo` digest bypass: **never enable it for a checking result**. Reproduction only, not a production PR. |

Unit eta changes definitional equality. Compact arithmetic and conversion
caches are also trusted kernel code and need expert review; these branches
are not a soundness certification. Some tracing/strategy switches remain
embedded in the implementation branches, not only in the diagnostic tail.

## Arena / pipeline

Repository: [theostos/rocq-lean-arena](https://github.com/theostos/rocq-lean-arena).

| Topic diff | Scope |
|---|---|
| [export-hints](https://github.com/theostos/rocq-lean-arena/compare/b7febb4...review/export-hints) | Preserve NDJSON reducibility metadata in `lean-export`. The experiment's converter had previously lived only in `_deps`. |
| [guarded-runs](https://github.com/theostos/rocq-lean-arena/compare/review/export-hints...review/guarded-runs) | Guard checker entry points, allow one heavyweight job, enforce cgroup memory limits and test process/service handling. |
| [atomic-checkpoints](https://github.com/theostos/rocq-lean-arena/compare/review/guarded-runs...review/atomic-checkpoints) | Atomic `.vo` promotion, evidence audit and the hash-pinned experimental launchers. Launchers under `work/` describe this machine's saved run, not a portable fresh-install command. |

This index is published on
[`review/cslib-review-map`](https://github.com/theostos/rocq-lean-arena/tree/review/cslib-review-map).
Exact review heads are in [review-stack.json](review-stack.json).

## Validation and reproduction

During the split: OCaml parsing checks passed on the changed sources. The
importer's `lean.ml`/`leanParse.ml` at each review head, and the three extracted
kernel conversion variants, were typechecked against the already built
experimental Rocq interfaces. This is **not a clean build of every branch**.
Parser-only and arena unit-test results are recorded in the manifest.

Earlier checks on the combined experimental implementation passed the original
FinLoop, `LawfulMonadStateOf.modify_eq`, `LinearMap.exists_ne_zero_of_sSup_eq`
and Int32 regressions, including save/reload checks and negative controls.
Those results do not establish that each newly split intermediate head passes
the same tests. The broader kernel `compact_peano.v` run was blocked by the
partial local stdlib build; do not report the full kernel suite as passing.

For a new validation, build the two stack heads together with a matching
stdlib, run the focused fixtures, then require the generated modules in a
fresh process. Run heavy jobs sequentially through the memory guard. A full
library result needs the expected EOF, no errors/skips, successful `.vo`
creation and fresh-process reload—not merely `Done!` or a line count.

The implementation snapshots were recorded as `snapshot/cslib-20260907`, capturing the
previously uncommitted sources. The final review heads match those runtime
sources byte-for-byte; only review documentation and added regression fixtures
differ. The split itself did not change the live source, binary, checkpoint or
hash-pinned runner.

### Local follow-up: direct unfolding dependencies

`fix/direct-unfolding-dependency` in the Rocq clone (commit `eb0b398bbf`, based
on `review/conversion-strategies`, not yet pushed) fixes a missed direct
dependency in the unfolding probe. `Std.HashMap.unitOfList_cons` now passes
its isolated reproduction, as do 20 focused checks and the saved-prefix load.
The live kernel and resume launcher include this correction; the published
snapshots above remain unchanged. See [reproduction and resume instructions](../work/hashmap-unit-cons-repro/README.md).

### Local follow-up: compact division/modulus fuel

The resumed run passed the HashMap theorem and reached **13,744,561**, where
`Int32.minValue_div_neg_one` overflowed the stack. Local Rocq branch
`fix/compact-fueled-arguments` (commit `b4db6046c3`, based on the preceding fix,
not yet pushed) makes conversion use the reduction machine's existing compact
numeral probe for division/modulus arguments, including computed successor fuel.
The original Int8/Int16/Int32/Int64 proofs now pass their dependency-only imports.
No importer or library proofs changed. The live kernel and resume launcher
include it; [details and tests](../work/int32-min-div-repro/README.md).

### Local follow-up: constructor-wrapper conversion

The next continuation reached **14,939,797**, `UInt32.toInt32_not`, then
overflowed. Local Rocq branch `fix/constructor-wrapper-conversion` (commit
`33ee807ae0`, based on the compact-fuel fix, not yet pushed) unfolds transparent
constructor wrappers before speculative record eta. This avoids forcing their
fields through nested projections. All five unsigned-to-signed complement
proofs and 30 focused checks pass with the combined experimental kernel.
The launcher now supports a separately sealed checkpoint through **15,001,015**;
that full-prefix run remains user-launched and unverified. See
[reproduction, tests and checkpoint commands](../work/uint32-not-repro/README.md).

### Local follow-up: record eta for stuck computations

The 15M checkpoint was saved and reloaded. The continuation then failed at
**15,281,867**, `Std.Tactic.BVDecide.LRAT.Internal.DefaultFormula.restoreAssignments_performRupCheck_base_case`.
Local branch `fix/stuck-record-eta` (commit `066b95cc9b`, based on the wrapper
fix, not yet pushed) restores Rocq's original record-eta fallback when a head
cannot unfold. The experimental early-eta optimization had dropped that fallback.
The unchanged theorem now passes its dependency-only import; a pure Rocq test
covers stuck matches/fixpoints and negative controls. The launcher supports an
explicit, hash-checked migration of the existing 15M checkpoint to this worker.
All 36 focused checks pass. The real continuation from that checkpoint through
the failing theorem also passes and saves successfully; full EOF is still unverified.
[Details and reproduction](../work/lrat-restore-repro/README.md).

### Local follow-up: binder scope in conversion probes

The next failure is **15,367,062**, `List.insertIdx_eraseIdx_of_le`:
the experimental congruence probe rebuilt copied closures at binder depth
zero, mistaking bound variables for external references and raising `Not_found`.
`fix/congruence-probe-scope`, based on `fix/stuck-record-eta`, applies each
side's lift and retains the local binder depth. The unchanged theorem, a pure
Rocq reproduction and all 40 selected checks pass. No importer or library proof
changed. This new branch is local; the four preceding `fix/` branches above
have since been published. The real continuation from the saved 15M checkpoint
through the failing theorem also passes and saves successfully. Full EOF
remains unverified.
[Details, tests and resume command](../work/list-insert-erase-repro/README.md).

### Local follow-up: bounded speculative congruence

The continuation reached **16,372,304**, `UInt32.toUInt64_shiftLeft_of_lt`,
then overflowed while comparing unused recursor branches. Local branch
`fix/bounded-congruence`, based on `fix/congruence-probe-scope`, limits the
nesting depth of speculative congruence before falling back to unfolding.
Opaque and local heads cannot start a limit, since congruence may be their
only checking route. The original theorem and six widening-shift variants
pass their fresh dependency-only imports; all 45 selected checks pass with
the combined experimental kernel. No importer or Lean proof changed;
the existing 15M checkpoint reloads successfully and its historical seal is
unchanged. The full continuation remains user-launched.
[Reproduction and resume command](../work/uint32-shift-repro/README.md).
