# Review entry point for the Mathlib integration snapshot

This document indexes the **implementation present on 18 September 2026**.
It is not a new whole-kernel audit and not the final report of a completed
Mathlib run. Keep it separate from the older CSLib review stack, candidate
experiments, and claims of exact Lean/Rocq equivalence.

Current task/status, updated 19 September:
[remote continuation brief](mathlib-homepc-next-steps.md). The objective is a
complete proof-checking Mathlib import through robust adaptations informed by
the pinned Lean kernel. The subsequent `ProofWidgets.Penrose.Diagram` timeout
at 58,521,298 remains unresolved; the latest documentation update adds no kernel
repair or validation result.

## Source of truth

- Kernel snapshot `d17b66af824e344393b126e57fbcec99174f926a`, diff against
  `f756383de2e66f63c95815c73838596d7d97c1c2`: 34 modified tracked files plus
  added native and OCaml tests. It captures the live source bytes; it is a
  preservation commit, not a claim that the large patch is a review-ready PR.
- Penrose follow-up `7b45cab763216a35b043afd356d1852f18e09b8d` is a child of
  that snapshot, changing exactly four kernel files and two checker files.
  It is delivered to `homepc` on `handoff/mathlib-20260918-penrose` through
  Git bundles, not yet published to GitHub. Its source-only transfer does not
  constitute remote build validation. The importer source is unchanged.
- Importer snapshot `5cf335ec68a41ad23dd720018a191f95b161a5cc`: source of the
  actual staged production importer `importer.rEXkanSl`, not merely the older
  development worktree. Relative to integration `d3e25df...`, it retains the
  definite-irrelevance registration check and the constructor-context fix.
- Arena handoff branch: orchestration, direct NDJSON and legacy diagnostic
  slicers, guards, repros and evidence. `scripts/handoff/arena_converter.py` is
  the exact converter used for slices; the older top-level converter differs.
- Reference: Lean 4.29.0 at `98dc76e...`, Mathlib `8a178386...`, lean4export
  `3de59f10...` with an explicit Lean 4.29 toolchain override. The newer Lean
  source checkout once used for comparison is **not** the reference kernel.

To start the kernel review in its clone:

```sh
git diff --stat f756383de2e66f63c95815c73838596d7d97c1c2 d17b66af824e344393b126e57fbcec99174f926a
git diff f756383de2e66f63c95815c73838596d7d97c1c2 d17b66af824e344393b126e57fbcec99174f926a -- kernel/conversion.ml
git diff d17b66af824e344393b126e57fbcec99174f926a 7b45cab763216a35b043afd356d1852f18e09b8d
```

## Implementation families

| Area | Principal files | Review questions / evidence |
| --- | --- | --- |
| Dependency-guided unfolding | `kernel/environ.{ml,mli}`, `kernel/conversion.ml` | Direct dependency/height metadata and bounded queries; cache lifetimes, opacity, definition-order preferences. See `docs/delta-unfolding-strategies.md` and the historical dependency-cache branch. |
| Sharing and substitution | `kernel/{constr,vars,hConstr,mod_subst}.ml`, `kernel/esubst.{ml,mli}`, `kernel/cClosure.ml` | Preserve DAG sharing while respecting binders, lifts, captured substitutions and universes. Avoid turning shared closures into exponentially duplicated trees. Native/private sharing fixtures and the alignment implementation report record controls. |
| Compact arithmetic | `kernel/cClosure.{ml,mli}`, `kernel/primred.{ml,mli}` | Literal views and checked operation registrations, predecessor/case interaction, update-frame ownership and overflow/fuel behavior. `compact_peano*` and runtime unit tests include negative controls. |
| Registration/trust boundary | `kernel/{retroknowledge,safe_typing}.{ml,mli}`, `kernel/typeops.ml`, `kernel/constant_typing.ml`, `kernel/modops.ml`, `library/global.{ml,mli}`, `vernac/vernacentries.ml` | Validate registered shapes/operations, universes and definite irrelevance; module substitution and persistence; no arbitrary “this is singleton” assertion. Do not equate this with merely choosing a faster unfolding order. |
| Unit-like conversion and eta | `kernel/conversion.ml`, `kernel/cClosure.ml`, `pretyping/inductiveops.ml`, `tactics/indrec.ml`, `vernac/declare.ml` | Recover and compare complete types, retain parameter/universe distinctions, respect typing witnesses and transparency; eta masks, saturation and recursive singleton eligibility. Includes earlier API counterexamples described below. |
| Conversion scheduling and memoization | `kernel/conversion.ml`, `kernel/cClosure.ml`, `kernel/typeops.ml` | Symbolic versus computational views; syntax-pair cache contexts; projections before expensive irrelevant record parameters; bounded speculative congruence with ordinary fallbacks. An exhausted shortcut is not a proof of equality or inequality. |
| Independent checker and compatibility | `checker/checkFlags.{ml,mli}`, `checker/{coqchk_main,mod_checking,values}.ml`, `kernel/inferCumulativity.ml` | Strict checking/explicit UIP policy, serialized flags and registration revalidation. Imported compatibility checks and strict native checks have different scopes. |
| Serialization and diagnostics | `lib/objFile.ml`, `vernac/himsg.ml`, diagnostic paths in kernel/checker code | Memory at save time, source/flag diagnostics, environment-controlled experiments. Inventory diagnostic switches and ensure none are enabled in acceptance runs. |

Every tracked modified kernel file appears in the groups above. Tests are in
`test-suite/success/`, `test-suite/unit-tests/kernel/`, and the preserved private
harnesses under `work/kernel-alignment-pass/`. The table classifies responsibility;
it does not assert that each individual delta is minimal or independently tested.

## Importer versus kernel

The older importer feature stack is documented in [importer-patches.md](importer-patches.md):
dependent projections, mutual/nested recursors, constructor ownership, modern
UInt32/Char/string representation, unit eliminators, error handling, metadata,
sharing and indexed checkpoints. Those documents are historical: compare their
listed heads with the integration snapshot rather than assuming every old
submission branch matches current production.

The later `SimpleGraph.IsSRGWith` failure (42,181,159) was an importer context
bug: recursive-field inspection must instantiate constructor universes and
extend the environment by parameters and preceding fields. The exact delta and
completed slice evidence are in
`work/mathlib-srg-release-20260917-v1/validation-receipt.json`.
Do not “fix” the resulting `lookup_rel` exception by treating missing binders as
irrelevant. Registration now also requires definite `Irrelevant`, not a test
which accepts unresolved relevance variables.

## Later production fixes and evidence trail

| Stage / motivating cases | Where to inspect |
| --- | --- |
| Initial alignment, sharing, unit witnesses, 5.8M/11.4M regressions | [alignment review](kernel-alignment-review-20260912.md), [implementation](kernel-alignment-implementation-20260912.md), `work/kernel-alignment-pass/README.md`, `work/mathlib-lift-to-discrete-repro/README.md`, `work/mathlib-with-terminal-repro/README.md`. |
| Computed singleton families, proof transports and larger projections | `work/mathlib-except-conds-repro/`, `work/mathlib-riemann-sharing-repro/`, `work/mathlib-two-view-release-20260914/validation-receipt.json`; source diffs/receipts distinguish promoted fixes from candidates. |
| Char successor/ordinal and recursor/congruence work | `work/mathlib-char-ordinal-repro/`, `work/mathlib-char-succ-repro/`, `work/mathlib-char-eliminator-release-20260914/validation-receipt.json`, `work/mathlib-char-succ-release-20260915/validation-receipt.json`. |
| Etale at 31,651,932; projection order, lazy source reduction, and qualification fixes | `work/mathlib-etale-repro/README.md`, `work/mathlib-etale-release-20260916-v9/validation-receipt.json`, `work/mathlib-integral-degree-repro/`. The README records failed candidates; the v9 release receipt is the later promotion boundary. |
| IsSRGWith at 42,181,159 | Constructor environments, as above. Focused qualification only; the user waived the full suite here. |
| Cotangent at 45,934,611 | [Cotangent report](../work/mathlib-cotangent-repro/README.md): corrected syntax-cache wrapper identity was insufficient alone; applied projection reduction through transparent aliases solved the production detour. Do not attribute the whole speedup to the cache fix. |
| AugmentedSimplex at 50,115,358 | [Simplex report](../work/mathlib-augmented-simplex-repro/README.md): full transparency-respecting type-head reduction for computed singleton discriminants, preserving complete-type checking. |
| PadicInt at 54,302,445 | [Padic report](../work/mathlib-padic-repro/README.md): nested cast inversion shares enclosing strategy work; symbolic recovery defers cast evaluation without poisoning closure state. Target-only recheck and same-cell retry/negative tests passed. |
| Penrose at 58,521,284 (SSH follow-up) | [Penrose report](../work/mathlib-penrose-repro/README.md): very large literal traversal, physical-memo collision behavior, application conversion fingerprints, large reflexive type comparison, and standalone serialized-value validation. The exact proof, fresh standalone target check, ten native groups, 18 focused fixtures and prior Padic replay passed on the laptop. The separate validation receipt pins that scope; it is not a remote validation or full Mathlib pass. |
| **Unresolved: `ProofWidgets.Penrose.Diagram` at 58,521,298** | The resumed production chunk passed the original proof, then timed out on this definition. [Raw failure evidence and hashes](../work/mathlib-penrose-diagram-failure-20260919/manifest.json). Samples show conversion/congruence; root cause is not established. No 60M checkpoint was saved. Investigate this target separately, retaining the earlier proof as a regression control. |

Not every directory has a README. For those, start with its release receipt's
`source_diff`, `scope`, `evidence` and `validated_inputs`; never infer validation
from the existence or name of a candidate file. Earlier diagnostic workers and
the PR #78 parallel experiment are not the current runtime.

## Lean alignment and assurance boundaries

The historical review identifies principles taken from Lean: scoped inference/
WHNF/equality caches, sharing-aware term traversal, lazy delta reduction,
projection scheduling, complete-type checks for the unit rule and compact Nat
operations. Rocq's moving-GC closures, cumulative universes, SProp and case
inversion require their own invariants; this is not a line-for-line kernel port.

The September 12 review also records concrete counterexamples/risks found during
development. Some were repaired in later qualification; that old document is not
the current defect list. Reconcile each with the implementation report and the
actual current tests. In particular:

- Lean Prop is translated to SProp and the foundation enables definitional UIP.
- The imported compatibility profile carries relaxed elimination flags; a
  successful `rocqchk -norec` target check does not mean strict validation of its
  dependency closure. Strict-with-explicit-UIP native tests are separate.
- Recursive singleton behavior has an explicitly documented Lean acceptance
  difference. Corpus acceptance alone does not justify a stronger judgment rule.
- Memoized successes, relevance masks and strategy retries require context,
  transparency, universes, substitution and mutable-closure invariants.
- Old diagnostic bypasses/experimental flags must stay disabled. A successful
  run must still reach the expected EOF, save an artifact and pass fresh reload.

## What can and cannot be reconstructed later

The Git snapshots preserve the integrated source and selected historical source
baselines/repro harnesses. Validation receipts preserve artifact identities,
commands, source diffs, outcomes and scope. A separate small evidence archive
preserves completed raw logs and metadata without committing multi-GB generated
artifacts. It excludes active output files and never exports credentials or
conversation/session stores.

This supports a detailed final review, but does not recreate deleted checkpoints
or every interrupted conversation. Some old reports are incomplete snapshots.
When the final implementation is selected, compare it against this handoff and
the clean base, classify retained versus superseded changes, and rerun the
relevant negative tests. Do not retroactively describe old partial validations
as a clean full pass of the final source.
