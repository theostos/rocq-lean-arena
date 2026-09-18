# Lie trace-form conversion timeout

The failure at original Mathlib line **28,200,411** was a 1,800-second
conversion timeout, not a rejected proof or a kernel assertion.

## Repair

The isolated theorem passes when destructive reduction sharing is disabled.
This remains true after removing all exploratory cache, unfolding-order and
projection-alignment changes. Sharing can replace symbolic applications in
mutable closure cells with expanded dictionaries; repeated comparisons then
lose their inexpensive common-head comparison.

The production change in `kernel/conversion.ml` is deliberately local:

1. Retain the existing bounded first attempt (256 conversion steps), using
   the caller's sharing setting.
2. On failure/exhaustion, start fresh closures for the existing typed,
   constructor/dependency-guided retry, with destructive sharing disabled.
3. Retain the remaining conversion fallbacks. No budget exhaustion counts as
   equality. No universe, positivity, guard or elimination check is disabled.

The retry derives a persistent environment; it does not change global options,
serialized profiles, the importer ABI, or the caller's environment. Untyped
conversion and conversion with the dependency heuristic disabled are unchanged.
This is a performance repair, not a claim of complete Lean/Rocq equivalence.

## Evidence

The dependency slice retains **all** proofs (2,866,592 stream records).
`proof-prefix/ProofPrefix.vo` was checked separately, in 1,299.50 seconds.
The patched target replay with normal global sharing, `proof-local-sharing-retry`,
passes in **58.79 seconds including prefix loading and checkpoint serialization**;
the import finishes before 20.37 seconds of process CPU time. Peak memory is
approximately 1 GiB. No proof was replaced with an axiom for this validation.

The full regression gate passed: private runtime tests, 15 native fixtures,
20 historical fixtures, 44 importer fixtures, fresh checkpoint sealing/reloading,
and 206 runner tests (204 passed, two opt-in tests skipped). Independent native
checking passed in compatibility and strict modes, as did all 11 strict-profile
controls. The final clean replay (`proof-final`) passed in **55.99 seconds**,
with import finished before CPU19.619s. The independent target-only check passed
as well, reusing the already checked dependencies as explained below.

Candidate worker: `ce98e4acc636eb5506b2294f6a6edb16bbf65b8503be2a0f09d8b8041cee28fb`.
The supplementary independent target check reuses the previously checked prefix;
it is not an independent recheck of all dependency proofs. Strict independent
native checks do recheck all their dependencies.

## Continuation

Restarted at 11:25 Europe/Paris on2026-09-14; service
`rocq-mathlib-alignment-5m-lie-sharing.service` was confirmed active/running.
Live status: `../mathlib-alignment-5m-20260913-with-terminal/progress.json`.

`resume.py` requires the pinned validation records before starting the existing
generation at **25,000,001**, preserving the 25M checkpoint and all producer
seals. Checkpoints remain spaced every 5 million lines, with the original
1,800-second declaration limit and 16 GiB memory guard. The assistant stops
monitoring after checking service startup. Full Mathlib verification remains
incomplete until the loop reaches EOF successfully.
