# Kernel alignment and robustness review — 12 September 2026

## Verdict

The latest bounded-quotation guard is a good **tactical containment fix**, not the final architecture. The accumulated patch set should not yet be described as a robust, Lean-aligned trusted kernel.

Three categories need to be distinguished:

1. Representation/performance changes worth keeping after hardening: compact naturals, sharing-aware traversals, appropriately scoped conversion caches.
2. Search strategies needing consolidation: early eta, projection congruence, dependency-directed unfolding, speculative arithmetic and retries.
3. Changes affecting accepted judgments or trust boundaries: singleton equality, registration certificates, elimination permissions, artifact loading and diagnostic switches.

The most urgent findings are a quality-polymorphic unit-registration defect and a compact-arithmetic update-frame defect. Both have concrete source-level paths; neither was executed as an end-to-end false-theorem reproduction during this review. There is also an **executed acceptance difference** between the reference Lean kernel and an existing Rocq singleton regression.

A successful Mathlib run would be valuable integration evidence. It would not discharge these negative-case obligations.

## 1. Scope, versions and evidence

This is a source review of all 27 tracked modified files in the live Rocq worktree, grouped below, against its clean base. It includes focused inspection of the importer/foundation boundary. It is not a formal verification, a complete importer audit, or a comprehensive execution campaign.

| Item | Reviewed reference |
| --- | --- |
| Rocq base | `f756383de2e66f63c95815c73838596d7d97c1c2` |
| Live Rocq | `_worktrees/rocq/compact-peano-view`, dirty; 5,556 insertions and 343 deletions relative to that base |
| Lean used by the Mathlib export | **4.29.0**, `98dc76e3c0a9b856c9b98726b713fb04fab16740` |
| Local newer Lean source | `85e60ac6d27bd44a415bf3cb42fb1cbeb6d9da63`, 4.33.0-pre; not the authoritative export kernel |
| Alternate Lean worktree | Same newer commit, with eager-marker handling disabled; not pristine upstream behavior |
| Export | Mathlib `8a178386ffc0f5fef0b77738bb5449d50efeea95`, exporter 3.1.0 |

The authoritative version comes from [source.json](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-ndjson/source.json). Exact Lean 4.29 sources were inspected using pinned upstream files; the installed 4.29 executable was used for the small kernel probe.

Snapshot hashes:

- `kernel/conversion.ml`: `e2f458e3f00e6e733a123ed54a6c7e920483ddfee20cb4850e0669750c1e9d9d`
- `kernel/cClosure.ml`: `e7ace0c5a0c5588490670274a0b31ddd0f03f21d9b8e306ef45bacc0db4924e4`
- `kernel/environ.ml`: `1dca5863d78566a9bf4f7129ed0cf533231a8bf4ae4f028fbe85d138c90ad9d9`

Evidence labels:

- **Executed**: a test run during this review.
- **Prior validation**: recorded by the preceding fix's harness; not rerun here.
- **Static**: established by code inspection and, where specified, a traced execution path.
- **Risk/obligation**: needs a focused test or stronger argument; not a demonstrated false acceptance.

No kernel/importer source was changed, no build or large replay was launched, and the running import was not altered. The new files are this report and the small Lean probe.

## 2. What Lean does, and what should be transferred

### Conversion strategy

The reference kernel proceeds through quick comparison, weak-head reduction, proof irrelevance and lazy delta reduction; later paths include applications, projections and eta. Regular-definition hints guide unfolding; equal-priority heads can both unfold. Failed same-definition congruence is remembered. Structure eta requires a constructor-shaped side. The direct unit rule is for fieldless structure-like types and checks complete inferred types. Nat arithmetic has dedicated fast paths. `eagerReduce` scopes more eager computation during argument checking. This is not a general “normalize everything first” policy. See [reference conversion](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp#L1058), [delta reduction](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp#L887) and [unit comparison](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp#L1046).

### Sharing and caches

Lean's checker state includes separate inference, weak-head, unfolding, successful-equality and failed-congruence caches. Its state also records eager-reduction scope. This separation is useful, but its cache keys cannot simply be copied into a different representation. [Checker state and interfaces](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.h#L25).

Its replacement machinery uses expression identity and binder offset within a fixed operation. Universe instantiation can skip unaffected expressions. Declaration admission also shares common expression structure. [Replacement cache](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/replace_fn.cpp#L16), [instantiation](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/instantiate.cpp#L15), [admission-time sharing](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/environment.cpp#L192).

Definition heights can be computed from directly occurring declarations' existing heights. This needs scalar metadata, not an all-pairs transitive dependency matrix. [Height construction](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/declaration.cpp#L193).

Lean's equality manager uses equivalence classes, with details such as hash filtering and union-by-rank. Do not interpret that as permission to add unrestricted transitive equality caching to Rocq's cumulative, context-sensitive conversion API. [Equality manager](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/equiv_manager.cpp#L21).

### Resource handling

Lean provides stack, memory, interruption and heartbeat checks. That does **not** amount to a fair, resumable scheduler for every speculative kernel operation. A shared work budget and resumable fallback are recommendations for this project, not an existing Lean guarantee. [Runtime checks](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/runtime/interrupt.cpp#L50).

The transferable principles are sharing preservation, separation of search from computation, clearly scoped caches, and explicit typing invariants. Raw C++ pointer techniques are not directly portable to moving-GC OCaml.

## 3. Review of the latest quotation guard

The previous run hit the 15 GiB aggregate RSS guard while checking `hasFTaylorSeriesUpToOn_pi`, not a natural declaration timeout. An optional eta type query copied a large shared argument through closure-to-term conversion. The 80-frame sample showed the copying but not its initiating caller. [Recorded diagnosis and validation](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-taylor-pi-repro/README.md).

The new [small_reification](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:950) preflight shares a budget of 4,096 expanded occurrences across the queried type and arguments. Oversized or unsupported inputs make the optional query return `None`, allowing ordinary conversion to continue. The query uses fresh closures and its own table.

This is the right direction for that failure:

- It counts expanded occurrences, not just distinct DAG nodes: a small shared DAG can denote an enormous tree.
- Declining the optimization asserts neither equality nor inequality.
- Fresh query state avoids marking the main conversion's closures as reduced under a different policy.

However:

- It covers one quotation route, not all calls to `term_of_fconstr`.
- It bounds the preflight, not reduction after it.
- Higher-order substitution composition can force work outside the simple occurrence estimate. Referenced unsupported substitutions are declined, but this is not a universal quotation bound.
- One subsequent weak-head reduction can still do substantial work before returning.

Prior validation is strong for this regression: original-order 19M→20M replay passed; the target took 32.496 CPU seconds there; fresh reload and the earlier 18M→19M replay passed. The harness also records 28 kernel fixtures, two closure unit tests, 44 importer fixtures, and 199 runner tests with two skips.

Recommendation: retain the guard as containment while replacing speculative full reification with a common closure-aware query interface. Do not proliferate independently tuned guards as the final design.

## 4. Correctness and trust findings

### C1 — Critical: global unit registration accepts unresolved relevance

**Static; high confidence. Newly introduced validator defect.**

[check_register_unit_like](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/safe_typing.ml:1964) accepts a constructor field when:

~~~ocaml
not (Sorts.is_relevant annot.binder_relevance)
~~~

But [Sorts.is_relevant](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/sorts.ml:566) returns false for both definite irrelevance and `RelevanceVar`. The latter can instantiate to a relevant `Type` or `Prop` field. The base [sort-polymorphism fixture](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/test-suite/success/sort_poly.v:58) already declares a box with such a field.

Registration stores the inductive identity globally. A quality-polymorphic box can consequently be certified as singleton even at an instantiation containing arbitrary naturals. The unit shortcut can then identify two same-typed neutral boxes. A common-type assumption does not rescue this case.

The importer duplicates the predicate in [its auto-registration test](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/cslib-ndjson/src/lean.ml:3723). Checker revalidation calls the flawed kernel validator too.

Required adaptation: accept only definitely irrelevant fields, or establish irrelevance for every permitted quality instantiation. If classification is instance-dependent, retain the instance in the certificate. Ordinary universe-polymorphic fieldless units need not be prohibited.

Required negative tests: registration of a quality-polymorphic data box must fail; relevant `Type` and `Prop` instantiations must not acquire singleton conversion; safe `SProp` controls remain supported.

I have not executed an end-to-end inconsistent theorem, nor established that the current Mathlib export exercises this defect. It nevertheless needs correction before claiming the registrar is safe.

### C2 — High: compact arithmetic crosses a sharing-update boundary

**Static reachable machine trace; high confidence. Newly introduced reduction invariant defect.**

[compact_peano_application_stack](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:2192) crosses `Zupdate` frames to consume a later application frame, then restores those frames around the computed result. A frame can belong to the function being evaluated, not the entire application.

A well-typed shape exposing the distinction is:

~~~text
let f := (let ignored := zero in add) in
(f zero zero, f (succ zero) zero)
~~~

With sharing enabled, evaluating the first use can produce:

~~~text
head add
stack: Update(f), Apply(zero, zero), ...
~~~

The shortcut consumes `Apply`, obtains numeric zero, then resumes with `Update(f)`. [The update handler](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:1059) writes zero into the cell denoting function `f`. The second use can observe a number where it expects a function.

The path uses ordinary closure allocation for the outer binding, entry through `knh` on the substituted variable, zeta reduction retaining the frame, and the successful shortcut at [cClosure.ml:2828](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:2828). It does not depend on malformed source syntax.

Required adaptation: respect update-frame ownership. The conservative initial repair is to decline acceleration across a leading update boundary; do not simply discard the frame. Test shared partial applications, nested lets, repeated calls with different arguments, and sharing enabled/disabled.

Precision: the helper also crosses shifts, but current successful shortcuts return closed numeric/Boolean values. The analogous open-variable capture example is therefore **not** an independent present defect. Keep the closed-result invariant explicit.

### C3 — High: unit classification discards the instantiated type

**Static API-level risk; high confidence in information loss, not an executed false-theorem witness.**

The recursive classifier can recognize singleton status at a particular instantiation but returns only the inductive identity. [same_unit_like_flexes](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:1241) and the [relative-variable path](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:1649) compare those identities, without parameters, universes, qualities or substitutions.

The flexible shortcut also occurs on public `typed:false` conversion paths. Individually well-typed inputs are not the same guarantee as a known common type. Some enclosing congruence checks may reject incompatible arguments later; this is not automatically an exploit through every caller.

Required adaptation: carry the instantiated type or a checked common-type witness. A boolean `typed` flag alone is insufficient justification. Add direct conversion tests for incompatible parameters, universes and qualities, alongside compatible and cumulative controls.

### C4 — Behavioral alignment: recursive singleton equality is stronger than the reference test

**Executed Lean result; Rocq counterpart has prior validation.**

The existing [unit_like_record.v](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/test-suite/success/unit_like_record.v:8) deliberately accepts reflexivity between arbitrary values of `Box (ProofBox P)`, where `ProofBox` has an irrelevant proof field and `Box` contains one such box.

The new [LeanUnitProbe.lean](/home/theo/Documents/github/rocq-lean-typechecker/work/kernel-alignment-review/LeanUnitProbe.lean) submits theorem declarations directly to the installed Lean 4.29 kernel with checking enabled. It uses a valid reflexive proof body but changes the requested result from `x = x` to `x = y`.

Observed output:

~~~text
KERNEL REJECTED kernelProbe: (kernel) declaration type mismatch, 'kernelProbe' has type
  ∀ (P : Prop) (x y : Box (ProofBox P)), x = x
but it is expected to have type
  ∀ (P : Prop) (x y : Box (ProofBox P)), x = y
KERNEL ACCEPTED kernelUnitProbe
~~~

The second test is a zero-field `Unit` control. This is a kernel acceptance difference, not an elaborator heuristic comparison.

It does not itself demonstrate logical inconsistency: stronger singleton equalities can be justified through eta and irrelevance. It does refute describing the broader shortcut simply as an implementation of the reference behavior.

Required decision: promise reference acceptance on translated terms, or document a broader translation extension and justify it separately.

### C5 — High robustness defect: registration replay is inconsistent

**Static; high confidence. New dependency-sensitive actions expose the problem.**

Registrations are prepended in [safe_typing.ml:811](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/safe_typing.ml:811), exported unchanged, and replayed with `List.fold_left` in [modops.ml:169](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/modops.ml:169).

For a fresh scheme registered in one module as `Peano type → double → add`, ordinary reload applies `add` first. Its update routine reaches the missing-scheme assertion in [primred.ml:53](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/primred.ml:53). Double has a scheme-synthesis fallback, but that does not protect add replayed before it.

The checker reverses registrations for validation, while subsequent ordinary import uses the other ordering. Module closing also reaches ordinary replay. Dividing registrations across libraries can hide this; successful Mathlib reload is insufficient coverage.

Required adaptation: one chronological, dependency-aware replay path. Missing prerequisites need structured errors, not assertions. Test each complete family saved in one module and loaded into a fresh process.

### C6 — High robustness risk: “monomorphic” certificates omit declaration context

**Static; medium-high confidence.**

The unary/binary checks at [safe_typing.ml:2042](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/safe_typing.ml:2042) inspect the constant's type syntax but do not establish an empty abstract universe/quality context. An unused abstract universe need not appear in `D → D`.

Equation checks construct empty-instance constants. Compact quotation also emits the doubling builder with [UnsafeMonomorphic.mkConst](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:854).

Required adaptation: validate the complete declaration context/constraints, or retain and instantiate them. Typecheck generated certificate applications. Add phantom-universe registration and quotation tests.

### C7 — High when enabled: diagnostic loading bypass and incomplete strict-checker profile

**Static; bypass is new, permissive checker policy is largely inherited.**

The presence of `ROCQ_DIAGNOSTIC_IGNORE_VO_DIGEST`, even with value `"0"`, bypasses dependency matching in [safe_typing.ml:704](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/safe_typing.ml:704) and [vernac/library.ml:332](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/vernac/library.ml:332). Ordinary import installs persisted registrations without rerunning their semantic validators. Mixing dependencies can disconnect certificates from the definitions against which they were checked.

This does not assert that the live import uses the bypass. It is a dangerous capability in the same build. The `objFile.ml` changes are tracing, not this bypass.

Separately, [checker/checkFlags.ml](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/checker/checkFlags.ml:13) honors several serialized checking/theory flags, including disabled guardedness, positivity, universe or elimination checks, and UIP. Checker success does not imply a strict safety profile.

Required adaptation: a fail-closed trusted profile, explicit theory/registration manifest, complete reporting of disabled checks, and exclusion of digest bypasses from trusted artifact production. Fresh `Require` is not independent rechecking of all opaque proofs.

## 5. Performance and implementation findings

### P1 — Dependency bitsets still have quadratic retained space

**Static complexity result; high confidence.**

The live [dependency cache](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/environ.ml:57) stores **transitive string bitsets**, not direct edges. Direct-occurrence scanning feeds recursive closure construction at [environ.ml:1333](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/environ.ml:1333); only afterward is membership tested.

| Version | Representation |
| --- | --- |
| Base Rocq | Transitive ordered sets |
| Separate `review/dependency-cache` branch | Direct edges, exact search, bounded pair-answer storage |
| Live reviewed worktree | Transitive bitsets with environment-local numbering |

The older [review map](/home/theo/Documents/github/rocq-lean-typechecker/docs/review-map.md:56) describes the separate architecture. Even that branch's capped answer cache did not bound search work.

For `n` independent definitions `dᵢ := aᵢ` with distinct axioms, each dependency set contains one bit. Yet its string extends to an increasing identifier position. Summed payload is approximately `n²/16` bytes: about 625 MB at 100,000 queried definitions, before maps/headers. Sparse graphs therefore suffer from padding too.

Dense sets can benefit relative to tree nodes, but this does not remove closure materialization. Bytewise unions add work; each cold body scan also allocates a 4,096-slot scratch table.

Positive: cache forks, numbering snapshots and invalidation on replacement/missing-name definition were handled carefully; no cross-fork identity contamination was found.

Required adaptation: scalar heights for ordinary ordering, direct edges where needed, and bounded secondary queries/answer storage. Exhaustion means `Unknown`, not a false negative. If bitsets remain, use sparse/dense adaptation and a memory cap.

### P2 — Existing budgets do not cover nested work

**Static; high confidence.**

- The 256 congruence counter is principally a nesting-depth limit, restored on return.
- The 1,024-step dependency probe delegates to unbounded transitive closure construction.
- Alias/unit fuels do not count all work inside a weak-head step.
- Fallbacks after failure cannot help while the first strategy remains busy.
- Other local/flexible unit-type routes and common-application probes still perform unguarded quotation.

See [congruence accounting](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:296), [dependency probing](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:1850) and [local-type inspection](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:1195).

Required adaptation: charge work where it happens—closure steps, substitution visits, graph edges, allocation estimates and arithmetic. Distinguish `NotApplicable`, `Unknown`, `NotConvertible` and `ResourceLimit`. Optional exhaustion should yield to the mandatory path, which must itself remain interruptible/resource bounded.

### P3 — DAG preservation is incomplete; shallow hashes have adversarial cases

**Static; high confidence on coverage and collisions.**

Good changes: universe-level substitution and universe collection remember physical terms; HConstr cache keys include binder-context identity.

Remaining gaps:

- [subst_instance_constr](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/vars.ml:439) still recursively traverses occurrences.
- [Module substitution](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/mod_subst.ml:470) caches renamed names, not transformed compound nodes.
- [Closure quotation](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:803) reconstructs shared arguments repeatedly.
- Equivalent, separately allocated binder contexts miss HConstr's cache before recursive descent.
- The dependency scanner's fixed direct-mapped table can evict shared nodes.

For `tᵢ₊₁ = f tᵢ tᵢ`, an unprotected tree traversal can require exponential work. A nonidentity substitution can also allocate an expanded result.

Additionally, [HConstr](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/hConstr.ml:171) and [Vars](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/vars.ml:360) use physical equality but shallow structural hashes. Distinct nodes with equal inspected prefixes collide; lookup can become quadratic. Equality remains correct—the risk is availability.

Required adaptation: end-to-end sharing-aware transformations, operation-scoped memoization and GC-safe identities/cached hashes. Include substitution, binder context and relevance where required. Do not remove context from open-term cache keys.

An inherited defect also surfaced: `map_kn` has no primitive-array branch, so references inside array values/default/type are not renamed. Add an array/module regression; this was not introduced by the registration substitutions.

### P4 — Conversion caches need a uniform policy

**Static; high confidence.**

The general successful-pair cache has useful safeguards: physical identity, stable closure identifiers, conversion problem, lifts, relevance/type context and bounded storage. It is not used as a bare boolean shortcut for generic universe-constraint inference.

But [projection comparisons](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/conversion.ml:2434) accumulate in an unbounded list with linear lookup, allowing quadratic work and closure retention.

Required adaptation: one bounded checker-owned policy with explicit keys/statistics. Preserve constraint outputs where applicable. Audit mutable-closure interactions with failed speculative branches. Ephemerons protect lifetime, not storage or work bounds.

Repeated queries against an unmarshalled environment with an invalid ephemeron can also remain cold: the temporary cache is not installed. Sharing within a query is not amortization across queries. Add reload-work tests.

### P5 — Compact arithmetic needs consumer and resource hardening

**Static; no end-to-end exploit asserted.**

Compact numeric representation and one-layer constructor exposure are good ideas. The latter corresponds to exposing zero/successor only when demanded. [Reference literal constructor exposure](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/inductive.cpp#L1191).

Beyond C2/C6:

- **Classify before evaluating.** The unary probe inspects its argument before identifying a supported operation; a function discarding an expensive argument should not pay for it merely because the probe looked.
- **Limit before allocating.** The million-bit power cap is checked after multiplication. Recursive boolean-list arithmetic can allocate excessively or overflow the OCaml stack first. Use stack-safe arithmetic, output-size checks and cancellation.
- **Separate resource exhaustion from nonrecognition.** Falling back to unary evaluation after exceeding an arithmetic budget can make matters worse.
- **Respect reduction flags.** Some argument retries replace requested flags with full reduction, preserving only transparency.
- **Cover rewrite continuations.** The audited constructor-pattern path does not expose compact numerals as constructors.
- **Clarify normalization versus quotation.** An internally normal compact value can quote to reducible doubling-builder syntax. Normal-form consumers need an explicit contract.
- **Respect abstract-constant handlers.** Direct environment lookup in predecessor recognition does not cover every private/abstract constant supported by ordinary closure lookup.

Locations: [arithmetic](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:85), [unary probe](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:1958), [full-reduction retry](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:2813), [rewrite matching](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq/compact-peano-view/kernel/cClosure.ml:2637).

The fueled division/remainder shortcut requires positive divisor and sufficient fuel relative to the dividend. This is an important semantic guard, not a work budget. An internal zero-divisor helper mismatch is currently excluded by that guard; it is not a demonstrated wrong result.

### P6 — Registration validation is promising, but needs a complete contract

**Static strengths plus assurance obligations.**

Most Peano validators disable acceleration and reset the oracle before checking symbolic computation equations. This is much stronger than trusting names or sample numerals. The checker delays validation until target declarations are available and rejects unresolved targets.

The fueled-worker certificate is more indirect: symbolic shape checks are combined with small observations of conditional/decision behavior. No malicious worker passing these checks was established. The remaining obligation is to justify why the checked shapes/observations determine the permitted computation, or use explicitly well-typed symbolic branch equations.

Specify each registration's preconditions, conclusion and persistence behavior. Test arbitrary adversarial registered implementations, not only expected importer definitions.

## 6. Comparison and patch coverage

| Area | Base Rocq | Current change | Required adaptation |
| --- | --- | --- | --- |
| Delta ordering | Oracle priority; optional dependency test on ties; one-sided tie choice | More wrapper, constructor and dependency preferences | Establish a reference-compatible baseline and measure deviations |
| Eta/singletons | Function/primitive-record conversion and SProp machinery | Registered units, recursive singleton recognition, earlier inspection | Fix C1/C3; distinguish semantics from search |
| Numerals | Inductive reduction plus existing primitives | Compact Peano closures and registered arithmetic | Keep representation; fix frames, certificates and consumers |
| Dependency storage | Transitive ordered sets | Transitive bitsets | Avoid closure materialization for routine ordering |
| DAG processing | Some sharing; tree-recursive transformations remain | Physical caches in selected traversals | Make transformations consistently sharing-aware |
| Memoization | Closure reduction tables | Pair cache, projection list, multiple probes | Unified scopes/bounds with universe/context obligations |
| Persistence | Original retroknowledge actions | Dependent registration families and validators | Replay ordering, declaration contexts, strict artifacts |
| Diagnostics | Original loader/checker behavior | Traces, alternate conversion, digest bypass | Separate observation from proof-affecting configuration |

The importer already translates regular heights to oracle levels and abbreviations to expansion. It overrides some regular hints for head expansion/power handling. Therefore “add Lean heights” is not the missing step: **use the metadata coherently and measure the overrides**. [Hint translation](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/cslib-ndjson/src/lean.ml:3638), [base Rocq ordering](https://github.com/rocq-prover/rocq/blob/f756383de2e66f63c95815c73838596d7d97c1c2/kernel/conversion.ml#L435).

All tracked changed files are accounted for:

| Files, relative to live Rocq | Review coverage |
| --- | --- |
| `kernel/conversion.ml` | Ordering, eta/unit rules, relevance masks, quotation, dependency probes, caches, budgets, diagnostic branches |
| `kernel/cClosure.ml`, `.mli` | Compact values, arithmetic, stacks, substitutions, closure identity and inspection interface |
| `kernel/environ.ml` | Dependency representation, cost, fork/invalidation and ephemeron lifetime |
| `kernel/hConstr.ml`, `kernel/vars.ml` | Hash-consing, context keys, universe collection/substitution, DAG gaps |
| `kernel/mod_subst.ml` | New registration identifiers and inherited compound-term/array limitations |
| `kernel/retroknowledge.ml`, `.mli`, `kernel/primred.ml`, `.mli` | Descriptors, duplicate consistency, scheme updates and replay prerequisites |
| `kernel/safe_typing.ml`, `.mli` | Validators, certificates, registration export/import and digest bypass |
| `checker/mod_checking.ml`, `checker/values.ml` | Revalidation timing/order and serialization action shapes |
| `library/global.ml`, `.mli`, `vernac/vernacentries.ml`, `vernac/himsg.ml` | Public registration wiring and diagnostics |
| `kernel/inferCumulativity.ml` | Compact-value leaf case |
| `pretyping/inductiveops.ml`, `tactics/indrec.ml` | Registration-based dependent-elimination relaxation |
| `kernel/typeops.ml` | Diagnostic conversion retries; body/type/universe checking remains present |
| `kernel/constant_typing.ml`, `vernac/declare.ml`, `lib/objFile.ml` | Primarily tracing; no unconditional acceptance found here |
| `vernac/library.ml` | Dependency-digest bypass |

Coverage means inspection/cross-checking, not a proof of every branch. Experimental deep-comparison branches and arbitrary fueled-worker certificates need dedicated adversarial tests.

## 7. What “aligned” should mean

The foundation implements a translation, not identical native theories: Lean propositions use Rocq `SProp`; the foundation enables definitional UIP and supplies equality, quotient and arithmetic bridges. [Foundation](/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/cslib-ndjson/src/Lean.v:1).

Specify three separate goals:

1. **Translation preservation:** accepted source declarations produce accepted target declarations of the intended translated types, under an explicit foundation/axiom profile.
2. **Behavioral fidelity:** conversion tests, including negatives, agree with the pinned source kernel wherever exact acceptance is promised.
3. **Robustness:** resource use, stack safety, sharing, cache scope, cancellation and persistence satisfy stated invariants.

An extension may preserve mathematical meaning while accepting more conversions. Document and justify that choice. Conversely, matching a positive corpus does not show rejection of bad proofs.

Dependent-elimination relaxations must follow validated singleton semantics, not an approximate classifier or uninstantiated global label.

An opaque unfolding hint is distinct from an unavailable opaque body. Eager-computation annotations are distinct from blanket transparency changes. Preserve these distinctions in the translation contract.

## 8. Recommended implementation order

### Phase A — correctness gates

1. Repair quality handling in unit registration and the importer predicate.
2. Repair arithmetic update-frame handling.
3. Preserve/check instantiated types in singleton equality.
4. Repair replay order and full universe-context validation.
5. Establish strict artifact/checker profiles without digest bypasses.

Use separate small patches, each with a negative or machine-invariant test first. Do not bundle them into another theorem-specific optimization.

### Phase B — consolidate conversion

Use one staged engine with explicit responsibilities:

~~~text
cheap structural checks
        ↓
ordinary closure reduction / metadata-guided unfolding
        ↓
bounded optional congruence, eta and arithmetic probes
        ↓
mandatory conversion fallback, itself interruptible
~~~

This is not a fixed ordering prescription for every constructor. Benchmark reference scheduling before selecting deviations.

A shared budget must cover nested helpers. Optional probes return success, decline or suspension; exhaustion is never cached as inequality. Use read-only/persistent views or isolated mutations: a fresh table alone does not prove closures are unshared.

Replace whole-term copying for inspection with closure-aware views retaining substitutions. Memoize necessary transformations per invocation with explicit binder-context treatment.

### Phase C — align ordering and caches

- Provide an exact-hint baseline without special-case overrides.
- Evaluate paired tie unfolding and failed same-head congruence caching on regressions.
- Keep reachability secondary and genuinely bounded.
- Bound all successful-comparison storage, including projection comparisons.
- Record reduction, quotation, graph-visit, cache-hit and allocation counters.

### Phase D — arithmetic and artifacts

Use reviewed, stack-safe big-integer operations while retaining validated links to Peano definitions. Demand only needed arguments, respect flags, and test every continuation.

Test serialization, substitution, reload and strict independent checking of each registration family. Record source/export hashes, worker identity, foundation profile, unsafe flags and certificates in the manifest.

## 9. Validation needed to close the review

| Test family | Required cases |
| --- | --- |
| Singleton safety | Quality-polymorphic fields; unknown/relevant fields; dependent/recursive records; incompatible parameters, qualities and universes |
| Exact Lean comparison | Direct kernel declarations; fieldless units, proof-field wrappers, constructor/neutral eta, opaque controls |
| Sharing updates | Function-valued let cells reused at different arguments; partial applications; shifts; sharing on/off |
| Arithmetic | Random small-number comparisons; boundaries; huge rejected powers; zero divisor; fuel limits; malformed workers |
| Flags/consumers | Beta/iota/zeta/delta restrictions; rewrite patterns; normalization/quotation; abstract constants |
| DAG transformations | Shared shapes under binders; nonidentity universes; arrays/cases/fixpoints; module substitution |
| Caches | Collisions; sparse/dense dependencies; forks; replacement; cold/warm/reloaded work; budget exhaustion |
| Persistence/trust | Complete families loaded fresh; checker replay; changed dependencies; every unsafe flag; bypass set to `"0"` |
| Integration | Previous failing theorems, original-order chunks, reload and strict independent checking |

Use deterministic counters/allocation bounds where possible. A small test finishing does not establish asymptotic robustness.

## 10. Reproduce the executed Lean probe

~~~bash
/home/theo/.elan/toolchains/leanprover--lean4---v4.29.0/bin/lean \
  work/kernel-alignment-review/LeanUnitProbe.lean
~~~

The same source initially ran through stdin with a 20-second timeout and 4 GiB virtual-address ceiling. It exited successfully, reporting rejection of the wrapped-proof case and acceptance of the Unit control. Unused-variable warnings are harmless.

The `expected` axioms supply types; their values are not used as proofs. Candidate bodies come from separately checked reflexive definitions. No malformed declaration is installed into the main environment.

## Bottom line

Keep the guard and useful representation changes. Correct trusted-boundary defects first. Then replace accumulating special cases with shared, closure-aware, resource-accounted machinery, assessed against the actual Lean 4.29 kernel.

The evidence supports **“an experimental importer/kernel with useful validated regression fixes and outstanding correctness/robustness obligations,”** not “aligned and certified kernels.”
