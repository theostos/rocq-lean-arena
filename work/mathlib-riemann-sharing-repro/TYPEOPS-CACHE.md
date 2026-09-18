# Application-domain conversion reuse

2026-09-14. Candidate worker:
`e17936ee0b3a7417d9452e083ccf9ef64cc1225eea856f2076a2456c6447bc3f`.
Final validation passed. The approved production service was started at
20:32 CEST from the sealed 25M checkpoint. Startup is confirmed: the service is
active, its preflight passed, and the reload imported the checkpoint state.
At handoff the reload job is serializing that state before the launcher
automatically starts the 25M-to-30M continuation. No ongoing assistant
monitoring is scheduled.

The final worker is unchanged. An additional checker-only correction uses
`default_conv_leq` for a constant's final body-type comparison, after
`Typeops.infer_type` and `Typeops.infer` have checked the two operands. This
matches the worker's typed conversion path. The previous untyped call omitted
the typed unfolding optimizations and caused the independent abbreviation
fixture to time out at 180s. With checker
`34488677886e8749696a3086edc2abbb5c9fb2da960881a682e7e01419305113`,
all 17 native fixtures recheck in 2.07s. This changes the available conversion
implementation at that already-typed call site, not the proof-checking scope.
Private checker tests reject forged final types, reversed cumulativity, and
malformed bodies; positive cumulative checks still pass.

## Change

Rocq already memoizes inferred types through `HConstr.Tbl`. However, distinct
applications can repeatedly compare the same inferred argument type against
the same instantiated domain. Each ordinary conversion starts new closure
tables. The Riemannian trace contains thousands of these application checks.

`Typeops.ApplicationConversions` now reuses completed successful comparisons
within one `Typeops.execute`. It is threaded explicitly alongside the existing
inference table; there is no global cache. Only the Lean-alignment heuristic
mode uses it. The inferred terms, checked declarations, and conversion rules
are unchanged.

## Safety and cost boundaries

- Keys contain the exact physical environment and an **ordered** syntax pair.
  This preserves local context, universe graph, relevance and transparency
  state, and the direction of cumulativity.
- Syntax matching uses the existing strict-universe `Constr.compare_head`
  comparison with a 1,024-visit limit. Exhaustion is a cache miss. Casts and
  unresolved variables are not traversed by that comparison.
- Only `Ok` from the ordinary fixed-universe check is stored. Exceptions and
  failed checks leave no entry. Successful lookup therefore reuses an already
  established judgment, not a heuristic claim of equality.
- Storage has 1,024 buckets and at most 4 entries per bucket. Collisions and
  eviction only reduce reuse. Entries contain immutable syntax, not mutable
  reduction closures. All retention ends with the typing invocation.
- Physically identical domains retain the existing reflexivity path without
  allocating a table. These are bounds on syntax visits and retained entries,
  not bounds on total kernel runtime or the sizes of individual syntax atoms.

Lean 4.29 has checker-local inference, WHNF and equivalence caches
(`lean-4.29-reference/type_checker.h` and `type_checker.cpp`). This adaptation
addresses that lifetime difference for application-domain checking; it is not
a claim that Rocq now implements Lean's exact conversion algorithm.

## Evidence so far

The continuous original-order continuation from 25,000,001 through 25,525,774
also passed, including all three reported Riemannian targets under the unchanged
120-second declaration limits. `riemannian-typeops-final/result.json` records
exit 0, 1,118.90s total (including loading and checkpoint serialization), and
artifact SHA256
`cff3d5ffb51a6dc453c48bdb8dff3997cbaf91de97951ac5591bfb9618b08692`.
The memory guard reported a peak of 8,697,356 KiB, below its 16 GiB limit.

The prepared original-order continuation from 25,505,940 through 25,525,774
passed all three reported Riemannian targets with 120-second declaration
limits. `riemannian-typeops-cache-prepared/result.json` records a successful
save in 759.70s total, including loading and full importer-state serialization.
One 61.3s inference call reused 5,277 of 8,849 application checks. Individual
NormedSpace conversions can still take several seconds.

Same-worker isolated replays also pass: Lie 54.85s, SSet 10.17s, derivative 130.33s
(all total process times, not individual declaration timings).
The corrected independent checker passes those saved target proofs in 14.59s,
0.90s, and 105.04s respectively. These continuation checks reuse the previously
checked dependency proofs; they do not recheck those prefixes from scratch.
It also rechecks the complete original-order 25,000,001–25,525,774 artifact in
514.84s with exit 0 and a 4,035,020 KiB guard peak. The first 25M lines remain
sealed dependency inputs, not a fresh independent recheck in this command.

The cache unit tests cover environment separation, ordered cumulativity,
fresh scopes, failure/exception poisoning, unequal sorts/arguments, shared
DAGs, wide applications, retention bounds, and real typing-machine rejection
after a successful earlier check. The new native fixture passes as well.

## Final approval

`../kernel-alignment-pass/final-gates-typeops-checked-serial` passed: 206 runner
tests (two skips), 17 native fixtures, 20 legacy cases, 44 importer tests,
fresh checkpoint/reload smoke, and the private runtime/cache/checker tests.
Both ordinary and strict native independent checks passed (about 2.04s each).
Strict checking rechecks dependencies and explicitly allows the existing UIP
bridge. All 11 strict-checker policy cases passed as well.

The immutable validation receipt and frozen runtime adapter are in
`../mathlib-two-view-release-20260914`. Production uses
`rocq-mathlib-alignment-5m-two-view.service`, starting from line 25,000,001,
with five-million-line checkpoints, the existing 1,800-second declaration
limit and 16 GiB memory cap. Producer seals and importer sources are unchanged.
This is validation of the listed cases and continuation, not a complete
Mathlib pass; completion still requires reaching the export's EOF.
