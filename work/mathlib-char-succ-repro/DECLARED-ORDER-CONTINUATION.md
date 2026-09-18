# Declared-order candidate, 2026-09-15

## Current v13 candidate (18:11 CEST)

V12 was REJECTED: all 17 native fixtures and 206 runner tests (two existing
skips) passed, but legacy case `direct_unfolding_dependency.v` timed out at
its 5-second bound. Its projected wrapper directly contains the opposite
constant, while the fixture intentionally assigns conflicting priorities.
The supervisor stopped; no production launch occurred. V12 source/test copies
are preserved in `rejected-declared-order-v12/`.

V13 checks direct occurrences before a decisive hint. That existing bounded
process query runs with `transitive:false`, so it does not search definition
graphs. Equal-priority cases still use the old constructor/dependency fallback.
This preserves strong direct evidence while avoiding transitive graph search
when declared hints suffice. The direct witness only chooses an unfolding
direction; ordinary conversion still establishes equality. This adapts the
projection/delta boundary to Rocq's constant-plus-projection-stack form; it is
not an exact implementation of all Lean projection rules.

The focused witness suite passed, and `direct_unfolding_dependency.v` now
passes in 0.55 seconds including reverse-direction and unequal-result controls.
Supervisor/resource tests pass 7/7 and 10/10. The full v13 batch has just begun;
the actual uninterrupted Riemannian timeout is NOT yet shown fixed.

- Worker: `9b79edfbe2e46420dda16da40e52793faa27dddb29e28420c583db672d773a00`
- Checker: `273b7adfa2213c572529f1119235e0a20153a570b65b3b63dac1088e80ebb8c7`
- Consumer importer: `../kernel-alignment-pass/importer.1lqiqwaI`
- Service: `rocq-mathlib-char-succ-validation.service`
- State: `finish-status.json`, `validation-v13/progress.json`,
  `validation-service.log`

The same 18-stage gate, unchanged memory/timeout limits, sealed 30M restart
boundary, and all-success-only promotion policy below apply. All sources and
binaries are pinned while it runs; do not edit or rebuild them mid-validation.

Progress at 18:17 CEST: all 17 native fixtures and all 20 legacy fixtures passed,
including the previously failing direct-dependency case, projection/eta cases,
LinearMap and bounded arithmetic. The 206 runner tests passed with two existing
skips, and the fresh original-order checkpoint/save/reload smoke passed. The
44-case importer suite is still running; the large original-order Mathlib
replays have not started on v13 yet. Those results must not be inferred from
v12's earlier ordinal success.

## Historical v12 attempt

Status at 18:05 CEST: native recursor/alias fixture and earlier ordinal slice
passed; the full v12 qualification pipeline has started. This is a candidate,
not a completed Riemannian fix or full Mathlib verification.

## Evidence and change

Both v10 and v11 timed out at original line 25,505,940 with the unchanged
120-second diagnostic limit. v11 removed eager environment copying from
optional type-head queries, but the uninterrupted replay still failed.
Its final two stacks show transitive dependency queries during application
type conversion. The prepared-prefix diagnostic separately completed the
requested proof-checking range on v11, and was deliberately stopped before
saving. Reloading that prefix does not reproduce the original-order failure.
See `TYPE-QUERY-CONTINUATION.md` and the diagnostic's `INTERRUPTED.md`.

Lean 4.29's `lazy_delta_reduction_step` chooses a head from stored reducibility
hints without a transitive graph search. The current Rocq importer already
transports those hints. The v12 candidate makes a decisive oracle order take
priority in `choose_unfolding_side`, without running the generic constructor
argument or dependency probes. Equal-priority cases retain the existing probe
ordering and fallback. Explicit constructor-driven Fix/Case demand, direct
aliases, and projected wrappers remain handled before this helper.

This is narrower than removing Rocq's translated-term scheduling wholesale.
Earlier oracle-first experiments did regress arithmetic; the newer explicit
recursor/alias fixes are now present, but the prior examples still need testing
on this candidate. No work budget, timeout, memory bound, equality rule,
opacity policy, or proof-checking flag has changed.

Pinned reference:
https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp

## Candidate identity and tests so far

- Worker: `0b3402d50d2f135f1350ead10efa044b6dc976fceba9dbf8f18ad142a817936d`
- Checker: `a30c7985003e671e5f5c4fee0a20ec80727b9f7d8acdc68a83d3197f178e4198`
- ABI-only importer rebuild: `../kernel-alignment-pass/importer.unHSWnMu`
- Full private witness suite passed, including 32/32 demanded-major cases,
  type-query sharing, and positive/negative type-witness tests.
- The ordering test verifies that decisive hints never invoke probes, and
  that tied hints preserve the old evaluation/result order.
- `abbrev_congruence_order.v`: exit 0, 0.93 seconds process time.
- Earlier `CharTarget.v`: exit 0, 10.16 seconds process time including load/save.
- Supervisor and resource-queue tests: 7/7 and 10/10 passed.

The v11 worker/checker and pre-change source/tests are preserved in
`pre-declared-order-v11/`. No checkpoint has been deleted or changed.

## Running qualification and restart boundary

Service: `rocq-mathlib-char-succ-validation.service`.
State: `finish-status.json`, `validation-v12/progress.json`,
`validation-service.log`.

All 18 stages rerun on the new worker. The broad native/legacy/importer gate
and its independent/strict checks run first, followed by uninterrupted
Riemannian and its independent check, then the Char/SSet/Lie/derivative stages.
No v11 success is reused as qualification of this worker.

After every gate passes, the supervisor separately verifies promotion and
resumes the sealed 30M generation. It keeps the 5M checkpoint interval,
1,800-second production declaration limit, 16 GiB/no-swap cap, and 3 GiB
reserve. It observes startup once and does not monitor production afterward.
Any failure stops without a production launch. Unrelated experiments remain
untouched. Do not edit pinned source or rebuild while this pipeline runs.
