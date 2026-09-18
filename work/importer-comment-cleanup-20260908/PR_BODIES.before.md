# PR titles and bodies

Copy the title and body; the base and evidence notes are not part of the PR body.
Bases and tips below match the published branches checked on 2026-09-08.
They are review bases, not necessarily branches available as upstream PR targets;
see [REVIEWING.md](REVIEWING.md). #68 and #69 are already
merged; external #72 and integration branches are not additional PRs here.
Error quotations below are excerpts, not complete diagnostics. Evidence paths
refer to the `rocq-lean-arena` checkout; historical full-run failures are
distinguished from isolated before/after tests. Full cslib checking is incomplete.

#70 is separate from all other topics. The rewritten stack has syntax/history
checks, but its fresh runtime gate remains pending; older test results below
are not a claim that every current tip has been revalidated. Recent kernel-only
conversion fixes, including the `blastAdd` fix, do not change these importer PRs.

## `submit/universe-instances` — separate existing #70

Review base: upstream `c8db093`; tip: `4cfef1a`. Update existing #70, not a new PR.

**Title:** Store complete universe-instance recipes

Store each Rocq universe instance as expressions over Lean parameters instead
of reconstructing an implicit source prefix and algebraic suffix. Declare only
the directly used source levels and synthesized levels.

Evidence: `UniverseBox@{a b}` exposes two parameters instead of four, but the
Lean fixture imports before and after. No cslib failure has been shown to
require #70: the controlled comparison also passes `Int64.toInt_minValue`
without it (`docs/pr70-cslib-comparison.md`). Do not use the historical Int64
constraint error as this PR's justification.
No other submission branch depends on this topic.

## `submit/dependent-projections`

Review base: upstream `c8db093`; tip: `f39444b`.

**Title:** Fix dependent projection types and relevance

Substitute preceding projections into dependent field types and compute
case relevance in the instantiated context. This addresses
`Std.Internal.Small.map` failing with `Illegal application (Non-functional construction)`
and incorrect relevance in Prop/SProp projections.

Evidence: the historical cslib error says `The expression "Set" of type "Type"
cannot be applied to the term "Set"` at line 2,256,856
(`_deps/lean-kernel-arena/_build/reports/cslib-after-universe-independent-punit/stderr.log`).
The isolated before/after cases are `DepRec.proof` and `Subtype.val`
(`work/next-pr-projections/README.md`). This branch now uses that standalone
commit directly on upstream, without #70.

## `submit/mutual-inductives`

Review base: `submit/dependent-projections`; tip: `c70d7ac`.

**Title:** Instantiate whole mutual inductive blocks

Importing `Lean.Meta.Grind.AC.EqCnstr` failed with
`missing Lean.Meta.Grind.AC.EqCnstrProof`, another member of its mutual block.
Declare and instantiate the complete block, including constructors and recursors.

Evidence: historical cslib failure at line 1,476,873,
`_deps/lean-kernel-arena/_build/reports/cslib-nested-relevance/rocq.stderr`.
Focused coverage includes `Tree`/`Forest` and polymorphic Prop/SProp instances.

## `submit/constructor-owners`

Review base: `submit/mutual-inductives`; tip: `c5c0d25`.

**Title:** Resolve constructors through their owning inductive

`Lean.Server.Watchdog.eraseFileWorker` failed with
`missing Lean.JsonRpc.ResponseError.mk` when the constructor was requested first.
Instantiate its owning inductive before resolving the constructor.

Evidence: full-run error at line 9,380,048,
`work/cslib-v2/CslibV2To9500000.indexed-gc5-4g.run.log`;
focused reproduction in `work/cslib-v2/constructor-owner-repro/README.md`.

## `submit/nested-recursors`

Review base: `submit/mutual-inductives`; tip: `ffebd00`.

**Title:** Preserve nested recursor computation with structural adapters

Earlier recursor adapters rejected `Lean.Meta.DiscrTree.Trie.casesOn` with
`Illegal application (Non-functional construction)` of `PUnit_unit`.
Generate coordinated `fix`/`match` adapters for the main and auxiliary recursors,
preserving computation through supported containers and records.
Track directly used universe levels when relaxing nested-container lower bounds.

Evidence: historical intermediate-adapter failure at line 1,210,790,
`_deps/lean-kernel-arena/_build/reports/cslib-sound-nested-prod/rocq.stderr`.
This is not a claim that all possible nested encodings are supported.
The topic also retains the lower-bound bookkeeping needed by nested containers,
without #70's universe-instance recipes or source-parameter pruning. It replaces
the old nested-container/mutual-nested/nested-record/SProp-scheme stack.

## `submit/primitive-record-eliminators`

Review base: `submit/nested-recursors`; tip: `4f1d24c`.

**Title:** Reduce record eliminators through primitive projections

For eta-enabled primitive records, implement eliminators through projections
and check conversion against the original body. Recognize field wrappers as
native projections and expose these eliminators before forcing their arguments.

Evidence: the focused neutral-pair fixture uses a ten-million-step fuel argument.
No isolated cslib declaration error is established for this optimization;
do not attribute a kernel-conversion failure to it. `NoEta` records keep their
ordinary eliminators.

## `submit/strict-import-errors`

Review base: upstream `c8db093`; tip: `a45a5db`.

**Title:** Report stopped imports and time declaration checking

Extend `Lean Line Timeout` to declaration checking, and report stopped imports
and premature EOF distinctly from completion. Slow conversion, such as
`Std.Tactic.BVDecide.LRAT.instInhabitedAction`, now reports `Lean import line timed out.`

Evidence: `work/cslib-v2/CslibV2EntryTimeout.after.run.log`, line 4,000,622
with a one-second limit; the earlier control required external termination.
This reports the timeout correctly; it does not make that proof check faster.

## `submit/reducibility-hints`

Review base: `submit/strict-import-errors`; tip: `30e6bb5`.

**Title:** Preserve Lean reducibility hints and opacity

Read exported abbreviation, regular-height and opaque hints, and map them to
Rocq's unfolding strategies. Keep `#HINT_OPAQUE` distinct from a genuinely
opaque `#OPAQUE` declaration; hinted proof bodies remain checked.

Evidence: cslib exports `Std.Tactic.BVDecide.LRAT.instInhabitedAction` with
`#REGULAR 5`. This preserves metadata; no isolated cslib type error is
attributed to this topic, and it requires the matching exporter.

## `submit/parser-sharing`

Review base: `submit/reducibility-hints`; tip: `dc7f180`.

**Title:** Preserve parser sharing in compact storage

Store parser nodes in persistent chunks and encode shared edges by index.
This reduces storage and serialization overhead for large exports without
duplicating shared expression nodes.

Evidence: a cslib save near line 8,940,683 previously hit the memory guard
(`memory guard: stopping workload at aggregate scoped RSS 3952088 KiB`,
limit 3,932,160 KiB); see `work/cslib-v2/README.md`, the chunked-storage section.
This is a resource failure, not a `rocq-lean-import` typing error.

## `submit/uint32-constructor`

Review base: `integration/upstream-pr72` (`6b885bb`); tip: `51f5666`.

**Title:** Register the exported UInt32.ofBitVec constructor

Register `UInt32.ofBitVec` instead of `UInt32.mk` for the BitVec-backed type
introduced by #72. This resolves the constructor name used by modern Lean,
including in `UInt32.ofNatLT`.

Evidence: the constructor and its use occur in the cslib export. The old lookup
implies `missing UInt32.ofBitVec`, but an observed prepatch diagnostic has not
been retained; do not present it as a measured failure. The older
`UInt32 -> Fin UInt32_size` versus `UInt32 -> BitVec 32` error belongs to #72.

## `submit/string-of-list`

Review base: `submit/uint32-constructor`; tip: `48c82a5`.

**Title:** Support String.ofList for string literals

Use `String.ofList` when `String.mk` is unavailable, applying the selected
function to the translated character list. This handles literals such as
`"Lean"` in `AddMonoid.nsmul_zero._autoParam` before `String.mk` is available.

Evidence: that literal occurs at cslib export line 52,113; `String.mk` appears
much later, at 19,987,629. The old lookup implies `missing String.mk`, but this
is source-derived, not a retained before/after error log; the focused fixture
checks dispatch, not the full byte-array String implementation.

## `submit/indexed-checkpoints`

Review base: `integration/importer-review-stock` (`1baf2aa`); tip: `f323e6a`.

**Title:** Store importer checkpoints as indexed snapshots

Pack parser nodes and expression-bearing metadata into an indexed snapshot,
restoring only the latest importer state when continuing a saved prefix.
This avoids retaining expanded importer graphs from every loaded checkpoint.

Evidence: checkpoint memory/storage optimization, not a declaration-type fix;
no standalone cslib error is attributed to this commit. The changed format
requires rebuilding older checkpoints, and current full validation deliberately
starts from line 1 without checkpoint reuse.

## `submit/compact-arithmetic`

Review base: `integration/importer-review-stock` (`1baf2aa`); tip: `6db923e`.

**Title:** Integrate compact arithmetic without replacing Nat comparisons

Encode natural literals compactly and register arithmetic with the experimental
Peano evaluator (`Int32.toInt_lt`: `Stack overflow.`). Retain source comparison
bodies: an earlier experimental replacement broke `Nat.beq.eq_def` with
`Illegal application` of `id_inst1`.

Evidence: `work/cslib-checkpoints/CslibBlocker5402976.compacttrace.out`
and `work/nat-beq-eq-def-repro/Fresh.baseline.run.log`; the source-preserving
repair passes in `work/nat-bool-source-repro/README.md`. Requires the experimental
kernel API; the Int32 result depends on both kernel and importer work.
Failed optional registrations retain the checked source definition.

## `submit/unit-like-eliminators`

Review base: `submit/compact-arithmetic`; tip: `7d2ef1b`.

**Title:** Simplify nullary unit eliminators

A match on a neutral `Unit` remained stuck, causing `Illegal application`
of `Eq_trans` in cslib's `FinLoop` totality instance. Using the experimental
kernel's unit conversion, generate a branch-only eliminator for eligible types
and check it against the original scheme type.

Evidence: `work/finloop-repro/FinLoop.baseline.run.log`, target
`Cslib.Automata.NA.FinAcc.instTotalSumUnitFinLoopOfNonemptyElemStart`;
the unchanged theorem passes after the adapter (`work/finloop-repro/README.md`).
Requires the experimental kernel's unit conversion rule, not merely an
unfolding optimization.

## `submit/translation-sharing`

Review base: `submit/unit-like-eliminators`; tip: `a8d47d3`.

**Title:** Cache translations by expression and binder context

Reuse translations of shared expressions in the same universe and binder context,
reducing repeated translation and allocation. Invalidate cached translations
when lazy declarations change projection or recursor dispatch.

Evidence: an earlier cache implementation reported `Translation cache mismatch
for application with required context 2, depth 4 and key [4; 1]` at `Nat.recAux`
in validation mode
(`work/review-importer-20260908/experimental-final-20260908/cache-validation/test-20-nat_boolean_adjacent.log`).
The final topic fixes that cache-specific regression; this was not a failure
of the original uncached importer. No isolated cslib typing error is claimed.
