# Cslib checking: review map

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

Each link below opens the **topic diff against its predecessor**. The branches
are stacked for review; they are not independent upstream PRs. Each has a
`REVIEW.md` with its scope, base and validation limits.

For example, in the importer clone:

```sh
git fetch fork
git diff fork/review/dependent-projections..fork/review/nested-fix-match
git worktree add ../review-nested fork/review/nested-fix-match
```

Use a separate worktree. Do not switch or rebuild a checkout used by a running
experiment.

## Importer

Repository: [theostos/rocq-lean-import](https://github.com/theostos/rocq-lean-import).
New stack base: `2fe11f4` (`integration/generic-cslib-current`). This base already
integrates the earlier PRs and features listed below.

| Topic diff | What to inspect / motivating case |
|---|---|
| [strict-import-errors](https://github.com/theostos/rocq-lean-import/compare/2fe11f4...review/strict-import-errors) | Failure propagation, stopped-versus-completed summaries and timeouts around deferred declarations. Explains the misleading partial-run `Done!`. |
| [constructor-owners](https://github.com/theostos/rocq-lean-import/compare/review/strict-import-errors...review/constructor-owners) | Instantiate the owner before its constructor. `Lean.Server.Watchdog.eraseFileWorker` requested a missing `Lean.JsonRpc.ResponseError.mk`. Includes a small `Box.mk` reproduction. |
| [dependent-projections](https://github.com/theostos/rocq-lean-import/compare/review/constructor-owners...review/dependent-projections) | Correct local context/relevance for dependent fields; retain projections for proof-only Type records without assuming record eta. See `dependent_sprop_projection`. |
| [nested-fix-match](https://github.com/theostos/rocq-lean-import/compare/review/dependent-projections...review/nested-fix-match) | Direct structural adapters for mutual/nested recursors. `Lean.Meta.DiscrTree.Trie.casesOn`; fixtures cover nested records, mixed fields and `below`. |
| [compact-kernel-integration](https://github.com/theostos/rocq-lean-import/compare/review/nested-fix-match...review/compact-kernel-integration) | Register Nat arithmetic/literal decoding with the experimental kernel; remove the superseded certificate transport path. `Int32.toInt_lt`, `Int32.ofInt_tdiv`. |
| [modern-core-foundation](https://github.com/theostos/rocq-lean-import/compare/review/compact-kernel-integration...review/modern-core-foundation) | Later UInt32/Char predeclarations and foundation changes, including the `Char.ofNatAux` path. Builds on the earlier modern-UInt32/String branches. |
| [reducibility-hints](https://github.com/theostos/rocq-lean-import/compare/review/modern-core-foundation...review/reducibility-hints) | Preserve Lean heights and hints; distinguish an opaque hint from genuine opacity. Supplies ordering information for large conversions, including `Int32.toBitVec_not`. Needs the arena exporter change below. |
| [nullary-unit-schemes](https://github.com/theostos/rocq-lean-import/compare/review/reducibility-hints...review/nullary-unit-schemes) | Register eligible unit types and check branch-only nullary eliminators. Fixes `Cslib.Automata.NA.FinAcc.instTotalSumUnitFinLoopOfNonemptyElemStart`. |
| [translation-sharing](https://github.com/theostos/rocq-lean-import/compare/review/nullary-unit-schemes...review/translation-sharing) | Translation/relevance caches keyed by shared expressions and their binder context. Addresses repeated traversal of large proof DAGs. |
| [indexed-checkpoints](https://github.com/theostos/rocq-lean-import/compare/review/translation-sharing...review/indexed-checkpoints) | Persistent parser chunks, indexed expression serialization and lazy state restoration. Addresses memory peaks when saving multi-million-line prefixes. Includes parser-only tests. |
| [importer-diagnostics](https://github.com/theostos/rocq-lean-import/compare/review/indexed-checkpoints...review/importer-diagnostics) | Remaining opt-in diagnostics and snapshot documentation. Reproduction branch, **not** an upstream PR. |

From `compact-kernel-integration` onward, use the experimental kernel stack.
The new importer stack is an incremental review of the current implementation;
it does not make every older branch ready to submit unchanged.

### Earlier PRs and branches

These have not been rewritten or deleted by this reorganization.

| Topic | Existing review entry |
|---|---|
| Hex bytes | [PR #68](https://github.com/rocq-community/rocq-lean-import/pull/68), `pr/hex-parser` |
| Identifier escaping | [PR #69](https://github.com/rocq-community/rocq-lean-import/pull/69), `pr/name-escaping` |
| Universe instances (`Int64.toInt_minValue`) | [PR #70](https://github.com/rocq-community/rocq-lean-import/pull/70), `pr/universe-instances` |
| Dependent projections | [`pr/projection-relevance`](https://github.com/theostos/rocq-lean-import/tree/pr/projection-relevance); later delta above |
| Mutual inductives | [`pr/mutual-inductives`](https://github.com/theostos/rocq-lean-import/tree/pr/mutual-inductives) |
| SProp scheme relevance | [`pr/sprop-scheme-relevance`](https://github.com/theostos/rocq-lean-import/tree/pr/sprop-scheme-relevance) |
| Modern UInt32/Char layout | [`pr/uint32-modern-dump`](https://github.com/theostos/rocq-lean-import/tree/pr/uint32-modern-dump) |
| String construction | [`pr/string-of-list`](https://github.com/theostos/rocq-lean-import/tree/pr/string-of-list) |
| Primitive-record eliminators | [`feature/primitive-record-eliminators`](https://github.com/theostos/rocq-lean-import/tree/feature/primitive-record-eliminators) |
| Nat decidable equality / compact literal decoding | [`pr/nat-deceq`](https://github.com/theostos/rocq-lean-import/tree/pr/nat-deceq), [`pr/compact-nat`](https://github.com/theostos/rocq-lean-import/tree/pr/compact-nat) |

The old `pr/nested-containers`, `pr/mutual-nested-recursor` and
`pr/nested-record-containers` represent the earlier adapter. Review
`review/nested-fix-match` for its current replacement. The old proof-producing
arithmetic, subtraction, comparison and `pr/char-of-nat` transport branches
are **not the arithmetic path used by the current experiment**. Definition
eta expansion from `feature/eta-long-record-definitions` is also no longer
applied by the current declaration path.

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

Both implementation forks have `snapshot/cslib-20260907`, capturing the
previously uncommitted sources. The final review heads match those runtime
sources byte-for-byte; only review documentation and added regression fixtures
differ. No live source, binary, checkpoint or hash-pinned runner was changed.
