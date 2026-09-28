# Mathlib in Rocq: the patch set

The scoped Mathlib export (100,001,405 records, ProofWidgets excluded) type-checks in a modified Rocq
kernel through `rocq-lean-import`, strict mode, zero admissions (2026-09-24, 11.4 h, one core).

Reproduce it with the [quickstart](QUICKSTART.md): use `kernel/nested-conversion`
(`01d35a1f01e5`) and `importer/survey-mode` (`643ff336974d`), the tips of the stacks below.

One branch per feature, stacked in the order below; each builds and passes its tests.
No environment variable is read; the only switch is `Set Kernel Conversion Dep Heuristic` (upstream).
Author of every commit: Théo Stoskopf. No PR opened.

## Rocq kernel — `theostos/rocq`, base `f756383de` (Rocq 9.3 dev)

| # | Branch | +lines | What | How |
|---|---|---|---|---|
| 1 | `kernel/checker-strict-mode` | 39 | `rocqchk -strict`, `-allow-uip` | Refuse UIP unless allowed. |
| 2 | `kernel/term-sharing` | 876 | Huge shared terms | Cells get an identity; lift, substitution, hash-consing, quotation memoised on sharing and iterative. |
| 3 | `kernel/compact-peano` | 2063 | Nat without unary expansion | `Register … as kernel.peano_nat_*`, checked; binary values in closures with a constructor view. |
| 4 | `kernel/dependency-cache` | 567 | "Does c1 unfold to c2?" | Bounded cache of direct edges, fuelled search. |
| 5 | `kernel/private-reductions` | 252 | Look without forcing | Budgeted reduction on a private copy of a closure. |
| 6 | `kernel/unit-like-conversion` | 1751 | Lean's eta for singleton types | `Register I as kernel.unit_like`; inhabitants of one registered type are convertible. |
| 7 | `kernel/conversion-strategy` | 2131 | Unfold the side that reaches the other | Dependency-first choice, projection congruence, bounded attempts (256, then 262,144 steps). |
| 8 | `kernel/peano-unfolding` | 295 | Keep arithmetic closed | Evaluate closed Nat operations before unfolding their wrappers. |
| 9 | `kernel/major-probe` | 67 | Iota before delta, as Lean | Reduce a recursor's major (512 steps) before choosing what to unfold. |
| 10 | `kernel/typeops-cache` | 130 | Type-check applications once | Cache argument conversions in `execute`. |
| 11 | `kernel/symbolic-views` | 169 | Retry on the original syntax | A closure keeps its source term for a bounded second try. |
| 12 | `kernel/conversion-memo` | 185 | Never prove the same equality twice | Memo of successful conversions per problem. |
| 13 | `kernel/shared-cells` | 378 | Equal closures are one cell | Content-addressed cells; memo keyed on a canonical context. |
| 14 | `kernel/nested-conversion` | 31 | Case inversion reuses it all | Nested conversions share cells and the step budget; depth-relative key. |

## Importer — `theostos/rocq-lean-import`, base `546979b` (upstream master, NDJSON merged)

| # | Branch | +lines | What | How |
|---|---|---|---|---|
| 1 | `importer/rocq-9.3-compat` | 9 | Build on the kernel's base | `Summary.Ref` → plain references. |
| 2 | `importer/indexed-checkpoints` | 422 | Save and resume long imports | Index-addressed DAG of parsed terms in the `.vo`; constructors resolve their inductive. |
| 3 | `importer/streaming-import` | 72 | Robust line loop | One timeout and one rollback point per line. |
| 4 | `importer/mutual-inductives` | 407 | Mutual blocks | One Rocq block, shared schemes. |
| 5 | `importer/nested-recursors` | 609 | Nested recursors compute | One structural path through containers and records. |
| 6 | `importer/primitive-record-eliminators` | 118 | Fast record elimination | Eliminators and projection functions via primitive projections. |
| 7 | `importer/unit-like-eliminators` | 40 | `match` on `Unit` reduces | Register unit-like types in the kernel. |
| 8 | `importer/reducibility-strategy` | 63 | Lean's unfolding order | Exported hints drive `set_strategy`. |
| 9 | `importer/compact-numerals` | 255 | Nat literals as values | Register Lean's Nat operations as Peano operations. |
| 10 | `importer/universe-instances` | 52 | Exact universe parameters | Only directly occurring levels. |
| 11 | `importer/translation-sharing` | 127 | Translate shared terms once | Translation cache on physical identity. |
| 12 | `importer/opaque-rollback-fix` | 7 | Correct rollback | Opaque table frozen with the environment. |
| 13 | `importer/name-escaping` | 17 | Any Lean name is legal | Escape at the Rocq boundary. |
| 14 | `importer/survey-mode` | 219 | Find all slow proofs in one pass | Timed-out theorems admitted and listed; never allowed into a checked import. Tooling. |

Fixtures: all pass, except `core.v`, `pnni.v`, `anomaly_print_projections.v` from branch 9 on (exports of an
older Lean whose `Nat.ble` does not satisfy the kernel's registration check).

## Status

- All 14 kernel and 14 importer branches were published to the forks on 2026-09-28.
- These exact heads checked the whole export on 2026-09-26: one process, no checkpoint, strict mode,
  100,001,405 records, zero error or admission, 10 h 50 min, peak 29.7 GB
  (`/media/…/rocq-mathlib-homepc-20260919/fullrun-20260925c`: `plan.json`, `run.log`, `result.json`).
  Run with `rocq repl -batch -bytecode-compiler no`: the VM compiler is not needed and costs memory.
- Publish the branch stacks and guide with `sh submission-push.sh` after configuring GitHub
  authentication. It does not delete or force-update branches.
