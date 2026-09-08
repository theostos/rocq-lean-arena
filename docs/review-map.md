# Cslib checking: review index — 2026-09-08

Check the original Lean library proofs through the importer, without manually
rewriting them:

```text
Lean library → Lean Kernel Arena NDJSON → lean-export → rocq-lean-import → Rocq
```

The kernel is experimental. Full cslib verification remains incomplete.
The fresh chain currently encounters `String.utf8EncodeChar.eq_def` at line
641,616; that repair is being validated separately and is not included here.

## Review convention

Each table is ordered from base to tip: compare a row with the preceding row.
These are local review branches, not independent upstream PRs. Nothing was
pushed during this split. Each topic has a `REVIEW.md`; exact heads and bases
are in [review-stack.json](review-stack.json).

Use the corresponding repository and a separate worktree. Do not switch or
rebuild the live experiment checkout.

```sh
# In the importer repository: only the new source-Nat fix.
git diff review/indexed-checkpoints..fix/source-nat-comparisons

# In the arena repository: only two-million-line checkpointing.
git diff review/checkpoint-resume..review/chunked-import
```

The earlier importer PRs (#68–70 and the original feature branches) are covered
by the [previous index](https://github.com/theostos/rocq-lean-arena/blob/a1ad29531948096d2e0afe77a7031708e39cda28/docs/review-map.md).
They are already incorporated in the importer base below; this split does not
rewrite those branches.

## Importer — theostos/rocq-lean-import

Base: `2fe11f4`.

| Branch | Commit | Scope / motivating failure |
|---|---|---|
| `review/strict-import-errors` | `3840f95` | Propagate errors and distinguish partial import from EOF. |
| `review/constructor-owners` | `dbea36a` | Instantiate an inductive before a constructor requested first. |
| `review/dependent-projections` | `8a1033a` | Dependent field types and relevance, including SProp instances. |
| `review/nested-fix-match` | `36a0297` | Structural fix/match adapters for mutual and nested recursors. |
| `review/compact-kernel-integration` | `f8046b1` | Connect the importer to checked compact-arithmetic registrations. |
| `review/modern-core-foundation` | `c6502cc` | Modern UInt32/Char foundation and predeclarations. |
| `review/reducibility-hints` | `e13420c` | Preserve Lean reducibility hints and definition heights. |
| `review/nullary-unit-schemes` | `705f9ef` | Branch-only schemes for eligible unit-like inductives. |
| `review/translation-sharing` | `47c9338` | Cache translation over shared expressions with binder context. |
| `review/indexed-checkpoints` | `6063313` | Preserve sharing across parser state and checkpoint serialization. |
| `fix/source-nat-comparisons` | `c9f9665` | Keep source Nat comparisons; fixes the original `Nat.beq.eq_def` proof. |

The new source-Nat commit includes seven focused tests and two unchanged
Lean dependency exports (about 84 KiB total). They are regression inputs, not
full library dumps. The older optional importer diagnostics remain on
`review/importer-diagnostics`, outside this implementation stack.

## Kernel — theostos/rocq

Base: `f756383de2`.

| Branch | Commit | Scope / motivating failure |
|---|---|---|
| `review/dependency-cache` | `9e03f679fc` | Bound dependency queries without retaining transitive closures. |
| `review/term-sharing` | `86cc3df709` | Preserve term DAG sharing in kernel traversals. |
| `review/reduction-registrations` | `10ae699a32` | Check and persist arithmetic/unit registrations. |
| `review/compact-peano` | `f0e7266ac7` | Evaluate registered Peano operations without unary expansion. |
| `review/unit-eta` | `d97781f8b2` | Unit conversion and lazy projection-type inspection. |
| `review/conversion-strategies` | `9d4289d1b2` | Unfolding order, congruence and conversion caches. |
| `fix/direct-unfolding-dependency` | `eb0b398bbf` | `Std.HashMap.unitOfList_cons`: recognize direct dependencies. |
| `fix/compact-fueled-arguments` | `b4db6046c3` | `Int32.minValue_div_neg_one`: inspect compact division/modulus fuel. |
| `fix/constructor-wrapper-conversion` | `33ee807ae0` | `UInt32.toInt32_not`: unfold constructor wrappers before speculative eta. |
| `fix/stuck-record-eta` | `066b95cc9b` | LRAT `restoreAssignments_performRupCheck_base_case`: restore stuck-head eta fallback. |
| `fix/congruence-probe-scope` | `42bb6c4a0b` | `List.insertIdx_eraseIdx_of_le`: retain binder scope in congruence probes. |
| `fix/bounded-congruence` | `1ff9ec82b3` | `UInt32.toUInt64_shiftLeft_of_lt`: bound speculative congruence depth. |
| `review/kernel-diagnostics-current` | `6b3b044c70` | Optional diagnostic tail; not a production PR. |

The six `fix/` commits were already committed; their order is retained.
The optional diagnostic tail is rebased separately. Its opt-in `.vo` digest
bypass must never be enabled for a verification result. Unit eta, compact
arithmetic, registrations and caches remain trusted kernel changes needing
expert review.

## Pipeline — theostos/rocq-lean-arena

Base: `b7febb4`.

| Branch | Commit | Scope / motivating failure |
|---|---|---|
| `review/export-hints` | `1b5f10a` | Preserve reducibility metadata during export conversion. |
| `review/guarded-runs` | `ad28f0a` | Single-heavyweight-worker and memory guards. |
| `review/atomic-checkpoints` | `f27ec58` | Atomic checkpoint promotion and evidence audit. |
| `review/checkpoint-resume` | `3b135b5` | Seal saved modules and check explicitly reviewed worker migrations. |
| `review/chunked-import` | `9a44d52` | Generate contiguous, resumable two-million-line chunks. |
| `review/checkpoint-generations` | `009ee60` | Start a new chain when representation changes; stage regression `Load` sources. |
| `review/cslib-repair-loop` | `2ae3fe4` | Local supervisor waits; bounded model turns repair failures; model-free gate retry. |
| `review/mathlib-export` | `9eb6c04` | Prepare pinned Mathlib exports with streaming/provenance checks. |
| `review/mathlib-repair-loop` | `4f55e16` | Queue Mathlib after verified cslib completion. |
| `review/checkpoint-cleanup` | `99c94ab` | Audit obsolete checkpoint candidates before explicit deletion. |
| `review/isolated-loop-tests` | `da1f74a` | Use temporary unit-test fixtures instead of operator checkpoints/toolchains. |

## Validation and exclusions

- The arena tip runs without local build/run artifacts: **169 tests passed**,
  two opt-in systemd tests skipped.
- Before this split, the combined implementation passed the 58-stage fresh
  Rocq regression gate. The seven source-Nat fixtures also passed.
- The newly split compiler heads have **not** been rebuilt in isolation:
  the active repair owns compilation. The review split does not establish
  that every intermediate branch builds.
- The full regression gate still requires the provisioned toolchains and
  dependency fixtures described by `checkpoint_generation.py`; those bulk
  local inputs are not vendored here.
- Runtime logs, compiled checkpoints, binaries, service state and abandoned
  experiment artifacts are excluded. No active compiler or supervisor source
  was changed by this split.

Run the lightweight tests from the arena review tip:

```sh
env -u GENERATION_SYSTEMD_TEST -u CSLIB_LOOP_SYSTEMD_TEST \
  python3 -B -m unittest discover -s scripts/tests
```

The existing Prop→SProp translation, universe specialization, logical assumptions
and importer `check_eliminations=false` path also require review. Successful
reloads check checkpoint compatibility, not every stored proof again.

For the current early-prefix failure, see the
[UTF-8 investigation](utf8-timeout-investigation.md).
