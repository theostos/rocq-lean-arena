**Delta unfolding: what differs, and which experiments to try next**

Read-only investigation, 2026-09-08. The recommended architectural experiment
is an incremental reducer that can return control to conversion before one
strategy consumes the declaration timeout. The strongest evidence is the
opposing Int8 and DHashMap failures: they require different choices between
exposing a wrapper and comparing record projections. Unconditional eta-first
and unconditional unfolding-first each regress one of these cases.

This is a design proposal, not an implemented or benchmarked replacement.
The running CSLib toolchain was left unchanged. The existing worker has passed
41 compiler regressions; that result belongs to the existing patches.

The comparison uses Lean 4.27.0-rc1, commit
`2fcce7258eeb6e324366bc25f9058293b04b7547`, the pinned upstream Rocq revision
`f756383de2e66f63c95815c73838596d7d97c1c2`, and our dirty experimental Rocq
worktree. Upstream already has an optional dependency heuristic; our changes
extend it substantially. These are the experiment's versions, not a claim
about the latest development branches.

The important source differences are:

| Decision | Pinned Lean | Pinned upstream Rocq / current experiment |
| --- | --- | --- |
| Head unfolding | Unfold a selected definition, simplify, reconsider the comparison. Equal-priority heads can both unfold. | Flex/flex already takes small steps. Flex/rigid and one-unfoldable-side paths instead request full weak-head reduction with the current transparency set. |
| Projections | Preserve projection structure initially; compare record sources, or expose a projection application before expanding the opposing computation. | Upstream preferentially evaluates record producers. Our patches add projection congruence and narrow wrapper exceptions. |
| Congruence | Applications of the same regular definition first compare instances and arguments; a failed attempt is remembered before unfolding. | Our speculative congruence has a depth limit, but nested reduction work can remain unbounded. |
| General record eta | Comes after lazy delta and projection handling. | Our early eta is useful for DHashMap, with constructor/projection wrappers excluded for Int8 and UInt32. |

References: [Lean conversion](https://github.com/leanprover/lean4/blob/2fcce7258eeb6e324366bc25f9058293b04b7547/src/kernel/type_checker.cpp#L875),
[Lean projection handling](https://github.com/leanprover/lean4/blob/2fcce7258eeb6e324366bc25f9058293b04b7547/src/kernel/type_checker.cpp#L1063),
[upstream Rocq conversion](https://github.com/rocq-prover/rocq/blob/f756383de2e66f63c95815c73838596d7d97c1c2/kernel/conversion.ml#L435).
The live implementation is in
[conversion.ml](../_worktrees/rocq/compact-peano-view/kernel/conversion.ml),
particularly lines 294, 347, 1221, 2273 and 2998.

Lean's outer steps are not bounded computations: recursor premises and
projection handling can invoke full reduction, and argument comparison is
recursive. A resumable scheduler would be a new design inspired by this
ordering, not a direct port of an existing Lean work-budget mechanism.

The importer already transports unfolding hints. The actual CSLib export
contains `#REGULAR` and `#ABBREV`; the converter and parser preserve them.
Lean's larger regular height becomes an earlier Rocq priority via `Level(-h)`;
abbreviations become `Expand`, and opaque *hints* become `Level 1`. Actual
opaque declarations remain distinct. Generated record eliminators and some
arithmetic definitions receive additional preferences, so the correspondence
is not exact. Equal-priority unfolding and when priorities are consulted also
differ. Merely adding the height metadata again would not address the gap.
See [hint transport](../_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py),
lines 410–452, [importer strategies](../_worktrees/rocq-lean-import/compact-peano-importer-current/src/lean.ml),
lines 3620–3655 and 4276–4283, and
[Lean's hint definition](https://github.com/leanprover/lean4/blob/2fcce7258eeb6e324366bc25f9058293b04b7547/src/kernel/declaration.h#L14).

The failure history gives a useful set of opposing examples:

| Evidence | What a broader strategy must preserve |
| --- | --- |
| [Int8/Int32 and DHashMap](../work/dhashmap-eta-repro/README.md): early eta forced bitwise fields; broad unfolding-first then regressed DHashMap into more than a million comparison steps. | Expose cheap wrappers, but retain eta for expensive or stuck record producers. |
| [Direct HashMap dependency](../work/hashmap-unit-cons-repro/README.md) and [UTF-8](../work/utf8-bitvec-two-repro/README.md): missing a direct occurrence and overvaluing a transitive witness chose the expensive side. | Distinguish direct evidence, transitive evidence, and unknown results. |
| [UInt32 shifts](../work/uint32-shift-repro/README.md): congruence explored branches that actual evaluation discarded. | Limit speculative descent while preserving required comparisons under opaque/local heads. |
| [Stuck eta](../work/lrat-restore-repro/README.md) and [binder scope](../work/list-insert-erase-repro/README.md): optimizations removed a fallback or reconstructed closures in the wrong context. | Preserve completeness and closure invariants while changing evaluation order. |

I would develop the strategy in three layers.

1. **Make reduction able to yield.** Introduce an internal operation that
   returns an exposed head, a blocked elimination with its demanded argument,
   or a suspended state after a work quantum. Preserve the current closure,
   substitution and stack instead of flattening the term. Conversion can then
   inspect the other side, try eta, or compare complete applications before
   resuming deeper computation. Start with the flex/rigid path and projection
   producers, where the existing failures provide direct evidence.

   The work accounting must reach inside `CClosure`, not just count outer
   delta calls. Our current
   [unfold_ref_with_args](../_worktrees/rocq/compact-peano-view/kernel/cClosure.ml)
   at line 3257 can itself fully reduce arguments of registered arithmetic
   operations. Beta/iota work and recursor scrutinee reduction can also be
   expensive. Replacing `all` with `betaiotazeta` everywhere would neither
   bound that work nor explain how a blocked eliminator should progress.

2. **Give alternative strategies a chance to run.** Let speculative
   congruence, eta and unfolding yield to another applicable route, retaining
   their progress. Exhaustion must mean “undecided”. Mandatory conversion
   must remain available with increasing work allowances or a complete
   fallback; an opaque head cannot lose its only checking route.

   The existing 256-call limit measures nesting, not total reduction work.
   A previous total-work cutoff regressed HashMap, while bounding opaque/local
   heads regressed `Nat.Linear.Poly`. The proposed change therefore needs
   resumable/progressive work rather than simply lowering a cutoff. Current
   whole-conversion alternatives run after failure; a route that times out
   before returning never reaches them. This is the main architectural gap.

3. **Make preference queries cheap and conservative.** Reuse declaration
   summaries for direct dependencies and wrapper shape, then inspect actual
   arguments/substitutions only as necessary. Bound transitive graph queries
   too. The present 1,024-node closure probe can invoke an unbounded graph
   search for every encountered constant; a bounded answer cache controls
   memory, not traversal time. Preserve “unknown” as a separate outcome and
   favor strong direct evidence over weak transitive relationships. These
   summaries guide the choice of reductions; they never establish equality.
   See [dependency search](../_worktrees/rocq/compact-peano-view/kernel/environ.ml),
   line 1398, and live `conversion.ml`, lines 1492–1653.

A smaller preliminary experiment is to use paired head unfolding on
equal-priority ties, keeping the imported heights and every other policy
fixed. Measure it independently before combining it with scheduling changes.
It may help align common heads, but sequentially reducing the first side can
still consume the timeout, so it is not the main solution.

Caching is a secondary, measurement-driven opportunity. Lean maintains
inference, WHNF, successful-equivalence and failed-congruence state, and shares
common subexpressions when checking a theorem. Our kernel also already has
sharing and successful-conversion caches. Count repeated semantic states
before adding another cache. A failed-congruence entry may suppress that
speculative route; it must never become evidence that the terms are unequal.
See [Lean checker state](../_deps/lean4-src-4.27/src/kernel/type_checker.h),
lines 26–35, [theorem sharing](../_deps/lean4-src-4.27/src/kernel/environment.cpp),
lines 192–205, and live `conversion.ml`, lines 1140–1187.

The implementation constraints are substantial: preserve binder depth,
lifts, relevance, universe state and transparency; keep the two mutable
closure heaps separate; and safely unlock or preserve pending update frames
when suspending. Pointer identity alone is not a semantic-state key. Cached
successes during universe inference would need appropriate constraint replay,
not merely a Boolean answer. An initial experiment should stay within the
existing typed, fixed-universe checking context.

Some problems lie outside unfolding strategy. FinLoop needs the existing
unit-conversion support and adapted recursor; compact Nat operations need
their own checked implementation. The older `eagerReduce` report is especially
easy to misread: its later Lean 4.29 ablation checked the stored theorem in
about four seconds both with and without the marker. The Rocq trace reached
100 million reduction steps inside head reduction, with zero version-correct
cache hits, and implicated naturals such as `fixedVar = 100000000`. That is
evidence for compact arithmetic, not for a marker-only fix or generic extra
memoization. This historical 4.29 result is separate from the pinned 4.27
source comparison above. See the [report's later diagnostic addendum](eager-reduce-conversion-report.md),
lines 563–632, rather than its superseded opening diagnosis.

After the active run, the experiment sequence should be:

- Add scalar counters for time/work in head reduction, argument forcing,
  congruence, eta and dependency queries. Avoid retaining terms for tracing.
- Benchmark the small paired-priority experiment separately, then prototype
  yielding reduction on the opposing Int8/DHashMap cases.
- Require the original fresh dependency exports and adjacent declarations,
  the 41-check gate, and negative controls for unequal fields, opacity,
  binder scope and exhausted speculative budgets. Preserve the same limits.
- Run relevant upstream kernel tests and independently recheck the resulting
  compiled artifacts; then perform a fresh full CSLib run with pinned inputs.

Reject a candidate that improves one member of an opposing pair while
regressing the other, turns exhaustion into a conversion verdict, or leaves
the measured bottleneck inside an uninterrupted reduction call. No general
speedup is established until these experiments are performed.

Audited live identities: worker
`5285fe33bb678eccdc41fd6de1ad09eed93bd8df243b0a3df1581de35f1ce578`,
`conversion.ml`
`b90b927b71d9ce83cd86e10844cf5fa334c8e254e30ae61a4a82bfaab3e1e750`,
importer plugin
`6304d147f1085e72463e7efc1d9bd9c2ff5920ddd95403102d2ca6f791a13bb1`.
