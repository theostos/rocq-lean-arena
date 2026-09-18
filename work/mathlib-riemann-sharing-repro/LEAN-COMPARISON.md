# Lean's actual conversion implementation versus the current experiment

Reviewed 2026-09-14 in response to the user's request. This is a source review
and experiment assessment, NOT an implemented or validated architectural repair.

## Later implementation status (2026-09-14, 20:15)

The later e17936ee worker adds bounded, context-specific successful
application-domain conversion reuse alongside Rocq's existing inference
cache. It passes the continuous 25M-to-25.525M Riemannian replay under unchanged
120-second declaration limits, plus the isolated Lie/SSet/derivative targets.
The 34488677 checker now uses typed conversion for the final comparison of
already-checked constant body/type judgments, matching the worker at that
call site. All four Mathlib artifacts pass independent continuation checks.
The final regression gate and strict checker tests passed. The approved
production service restarted at 20:32 CEST from the sealed 25M checkpoint.
See TYPEOPS-CACHE.md for the implementation boundaries and complete results.
These results do not establish full Mathlib verification or exact kernel
equivalence.

## Historical experiment status (2026-09-14, 17:45)

The review below records the pre-experiment implementation; its Rocq line
numbers and missing-feature inventory are historical. Subsequent work added
symbolic closure views, failed-congruence caching, stable complete application
keys, and an abbreviation-first path. None is approved as a full Mathlib fix.
See `TWO-VIEW-EXPERIMENT.md` for both successful and failed replay records.

A further concrete omission was found in `fast_test_under`: identical mutable
closure cells under identical relocations recursively inspected their children
instead of immediately succeeding. The new identity guard is tested on a
30-level shared application DAG. The test failed before the guard and passes
after it, with negative controls for unequal relocations and distinct variables.
This is analogous to Lean's early identity test (`quick_is_def_eq`, line742),
but does not establish the same asymptotic behavior for different closures.
No production restart has been authorized by validation results yet.

The current candidate has one policy that passes the proof-preserving isolated
Lie57.16s, SSet10.20s and derivative155.38s replays (total loading/checking/
saving time). Original-order Riemannian FAILED at25,505,940 under the120s
declaration limit; broad final gates have not run.
These timings do not establish an end-to-end Mathlib pass.

| Concern | Lean reference | Current Rocq adaptation |
| --- | --- | --- |
| Symbolic structure versus evaluated values | Immutable expressions and separate core/full-WHNF caches | Keep reduced closure sharing, plus a separately retained symbolic view for bounded recovery |
| Shared syntax already identical | Early identity/equivalence test | Physical cell identity succeeds immediately only under equal relocations |
| Repeated failed same-head comparison | Failed-congruence cache, not a negative equality cache | Bounded exact application-process keys; failure selects unfolding, never rejects equality by itself |
| Abbreviation arguments | Same-head shortcut only for regular definitions | Respect transparent Expand definitions before comparing their arguments; retain opaque congruence |
| Recursor branches discarded by computation | Demanded primitive recursor reduction before application congruence | Read-only bounded detection of a transparent lambda/fix wrapper with a visible constructor major argument, then ordinary unfolding |
| Unit-type comparisons | Typed unit-like check late in conversion | Short-circuit failed shallow classification and defer expensive full type reconstruction; keep checked type compatibility |

The two-view implementation exposed and repaired a real invariant bug:
the reduced view's Ntrl flag does not certify that a restored symbolic view
is beta-normal. The restored view must pass through the reduction machine.
A checked beta-redex test failed before this correction and passes after it;
the original-order replay also passed the previously failing Witt-vector line.

The new recursor fixture deliberately leaves nat_rect at regular priority.
The earlier forced-Expand control is NOT validation. The restored fixture now
passes0.59s and includes parameterized/ordinary recursors, opaque and partially
applied functions, and unequal-result negative cases.

Remaining differences are explicit: Rocq still uses mutable closure machines,
context/relocation-aware keys, bounded speculative recovery and dependency
heuristics. Lean uses a different expression representation and checker-level
cache lifetime. The new bounds count conversion steps, not all reduction work
or elapsed time. These changes are not a claim of literal algorithm identity,
complete kernel equivalence, or guaranteed termination within a time limit.

## Reference

The Mathlib export records Lean 4.29.0, commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740` in
`../mathlib-ndjson/source.json`. Files in `lean-4.29-reference/` were retrieved
from that exact upstream commit. The default local `_deps/lean4-src` checkout is
at a different revision; it must not be used to claim exact export alignment.

## What Lean does

1. `type_checker.cpp:1058`, `is_def_eq_core`: quick equality first; initial
   weak-head reduction leaves global definitions and expensive projections
   symbolic; proof irrelevance; lazy delta; projection handling; ordinary
   application comparison; function/structure eta; final unit-like check.
   Nat/reflection/native reductions also have dedicated paths.
2. `type_checker.cpp:886`, `lazy_delta_reduction_step`: choose definitions using
   reducibility hints, unfold one selected head, simplify and reconsider. On
   equal-priority hints unfold both sides. For the same regular definition,
   try universe-instance and argument congruence first. Failed congruence is
   remembered (`failed_before`, `cache_failure`) so that route is not repeated.
   This cache means that the shortcut failed, NOT that the terms are unequal.
3. `declaration.cpp:193`: regular definition height is one plus the maximum
   existing height of constants occurring in its value. The hint comparison
   prefers the larger regular height. This does not require a transitive
   all-pairs dependency matrix or repeated dependency graph traversal at each
   conversion decision.
4. `type_checker.cpp:1010`: matching projections can lazily compare record
   sources before evaluating their fields. The one-unfoldable-side path also
   tries to expose a projection application on the other side before repeatedly
   unfolding an expensive definition.
5. `type_checker.h:26`: separate inference, core-WHNF, full-WHNF, successful
   equivalence, failed-congruence and unfolding caches. `environment.cpp:192`
   creates a checker per theorem and shares common expression structure before
   checking; the checker is reused throughout that declaration.
6. `type_checker.cpp:499` and `:403`: unfolding/reduction returns expressions
   and caches results separately from their input expressions. Sharing immutable
   expression structure is not the same as destructively replacing all views of
   a symbolic application with an expanded dictionary. `replace_fn.cpp:16`
   memoizes a traversal by expression identity and binder offset within a fixed
   replacement operation.

There is no counterpart here to our new weighted 12-mode retry loop. Lean's
recursive argument tests and demanded recursor/projection reductions are not
individually bounded time slices either. Its interrupt checks are not a proof of
a worst-case runtime bound. Calling our retry scheduler a direct Lean port would
be incorrect.

## Historical mismatch inventory (before this experiment)

- The pinned importer already translates regular heights to `Level(-height)`
  (`src/lean.ml:3646`), but some wrapper/power preferences override them.
  Adding height metadata again is not the missing fix.
- `conversion.ml:428` can prefer constructor/dependency observations over the
  oracle. Equal-priority fallback chooses one side, unlike Lean's paired step.
  Several one-unfoldable-side paths request full transparent WHNF.
- `conversion.ml:1910` tries same-head stack congruence but does not have Lean's
  corresponding failed-congruence cache. Its optional depth bound is not a bound
  on all reduction work performed inside the attempt.
- `conversion.ml:2641` implements projection-source congruence under additional
  conditions. Stuck projections can also occur as `Zproj` frames over `FFlex`,
  not only as `FProj/FProj`, so matching the surface branch is insufficient.
- `cClosure.ml:338` updates mutable closure contents. Disabling these updates
  preserves useful heads for the Lie example but causes repeated work in other
  examples. Lean-style persistent syntax plus reduction memoization is not
  equivalent to globally turning off Rocq reduction sharing.
- `clos_gen_conv` creates fresh local caches for each retry. Retrying whole
  conversions discards progress rather than reproducing Lean's checker-level
  reuse. Rocq cache keys must still account for context, lifts, universe and
  relevance conditions; blindly copying Lean's expression-pair keys is unsafe.

## Measurements and decision

The weighted candidate passes isolated `spineEquiv` (10.20s including load/save)
and the all-proof derivative dependency (250.37s; ordinary-conversion diagnostic
control 95.35s). It then fails the unchanged 120s Lie regression target limit.
It is NOT approved and production remains stopped. These are selected legacy
replays with all dependency proofs retained, not an end-to-end NDJSON pass.

The next architectural investigation should preserve both original symbolic
structure and memoized reduced results, and measure local unfolding/projection
decisions and repeated failed congruence. Prior Lie experiments already tested
scalar paired delta, projection alignment and extra success caches without
solving that case; simply repeating those changes is not justified. Any new
design needs the opposing Lie/Riemannian/SSet cases together, unchanged checking
rules and time limits, negative controls, strict native checks and proof-preserving
replays before the sealed 25M checkpoint can be resumed.

## Upstream sources

- [Conversion and reduction](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp)
- [Checker caches](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.h)
- [Hint semantics](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/declaration.h)
- [Definition heights](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/declaration.cpp)
- [Theorem admission and sharing](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/environment.cpp)
- [Binder-aware replacement caching](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/replace_fn.cpp)
