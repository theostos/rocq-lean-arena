# Shared/symbolic conversion retry — September 14, 2026

**Historical experiments below are rejected, not the current candidate.**
See `TWO-VIEW-EXPERIMENT.md` for the active structural investigation. Production
is stopped and the draft `resume.py` must not be used.

## Current experiment: weighted strategy scheduling

The current worker is `a706187c2cd0fc2209b9cfe5eafd28ada4545dff0a581ebd937987d048080089`,
checker `39bb45296b16e7d7cb437af5cd2576a3999d33c2cee0b0e0eaca3b771ef0ab1d`,
conversion source `2c16e5a01bfa58cad7d44272bbf04a0454cff6aa8915c4bff4735a1c5112a68b`.
Source matches `conversion.weighted.ml`. It is **not yet approved for production**.

Equal allowances across twelve modes still timed out on the derivative at 180s.
Disabling direct-constructor argument prioritization alone did not help either
(`derivative-no-direct`). The weighted scheduler instead gives ordinary shared
conversion 32 times each heuristic's allowance, retaining the other strategies
and the geometric retry policy. This is an empirical scheduling choice, not a
new conversion rule or a guarantee about reduction time.

`test-weighted.sh` passes. The exact derivative (`derivative-weighted`) passes
with all proofs retained in 250.37s including load/save, versus 95.35s for the
ordinary-conversion diagnostic control. The test used a 600s line limit;
production's 1800s line limit is unchanged.

The all-proof `sset-prefix` passes in 99.57s. `sset-weighted` passes the exact
`spineEquiv` target in 10.20s including load/save (the import transaction is
5.288s, mostly serialization). However, `proof-weighted-sharing` in the Lie
reproducer FAILS its unchanged 120s target limit (132.87s total). Consequently
this candidate is **rejected for promotion**, not a repair of all known cases.
The full Mathlib run has NOT been resumed. Riemannian targets and broad gates
were not run on this rejected candidate. `resume.py` remains an unapproved draft.

The user requested direct comparison with Lean's implementation. Exact 4.29
sources matching export commit `98dc76e3c0a9b856c9b98726b713fb04fab16740`
are saved in `lean-4.29-reference/`; the default local Lean checkout has another
revision and is not the authority. See `LEAN-COMPARISON.md`. Lean has no analogous
12-mode weighted retry loop. Preserve symbolic expressions and reduction cache
results separately, and investigate local unfolding/projection decisions, before
treating a retry-weight change as architectural alignment.

## Earlier equal-allowance strategy scheduling (not approved)

This experimental worker was
`7d04b265bbb90d9702d955d32a7f52011614e89cec048ba32d144138af4bdf60`, checker
`7a2a968519d0d5125052ee222973849eb374cc0b3829aa450d08c6b0a4e306ae`, conversion
source `3ad3e2bb5553e5d308ca42b6a523a06ffdaef69856ee50586143346693a7f07e`.
Source matches `conversion.portfolio.ml`. Only conversion.ml changes in the
kernel; public interfaces and the pinned importer are unchanged.

The derivative control with ordinary conversion (`derivative-plain`) passed
in 95.35 seconds total, import completed before process CPU73.791s. Conversely,
merely removing the 256-step cap from the original dependency-first attempt
(`derivative-original-strategy`, trial worker `1e6bc764...`) still timed out at
180 seconds. That one-line control has been removed.

This demonstrates a gap in the two-mode candidate: it endlessly retries its
constructor/dependency strategies and never reaches a useful ordinary fallback.
The new `retry_conversion_strategies` keeps all six existing strategy combinations
eligible, with both sharing modes (12 choices when sharing is enabled), using
geometrically increasing conversion-step allowances starting at 256. Completed
negatives retire; exhausted choices remain eligible. The initial cheap attempt
is still present, but exhaustion does not discard that choice forever. No new
conversion rule is added. These are still not wall-time/all-reduction budgets.

`test-portfolio.sh` passes all private tests. The expanded test
`../kernel-alignment-pass/conversion_schedule_test.ml` covers every winner in
1/2/4/12-choice schedules, retirement, exceptions and saturation; it is integrated
into the ordinary alignment gate. `derivative-portfolio` is currently replaying
the exact lemma under the debugger. The Lie theorem must be rerun on this worker;
the four original Riemannian/SSet targets and the broad gates remain pending.
`resume.py` is only a draft, pinned to the earlier rejected worker; do not run it
or approve this build until all validation records are updated and successful.

## Earlier two-mode candidate (not approved)

Status: candidate built; private tests and the earlier Lie proof replay pass.
The combined prefix exposed a slow dependency,
`iteratedFDerivWithin_eventually_congr_set'`, at extracted line 2,499,931.
The agent interrupted this test after over nine minutes on that declaration
(2094.78 seconds total replay); it is NOT a completed or timeout-failed prefix.
The narrower proof-preserving prefix now passes (`derivative-prefix`, 785.40s;
artifact `3298cbd7041801b4519974e0520b2356b31b9f04ebc96516cc00da422b52479a`).
Its target reproduces a 180-second timeout under the startup debugger
(`derivative-trace`, 190.36s including load), without any abstracted proofs.
Calls 502 onward repeatedly compare `product/0 <> lambda/1`; after the cheap
first attempt, both constructor/dependency-guided sharing modes take increasing
work and do not complete. `derivative-plain` tests the ordinary conversion path
with only the pre-existing NO_DEPENDENCY_FIRST diagnostic switch changed.
Attaching GDB/perf to the earlier worker was denied by the OS; no system
permissions were changed. This candidate is NOT approved to resume.

## Failure and cause

The production attempt `20260914T092520303431Z` in
`work/mathlib-alignment-5m-20260913-with-terminal` timed out after 1800 seconds
at original line 26,774,107, `SSet.Truncated.StrictSegal.spineEquiv`. The periodic
SIGUSR1 messages are diagnostic samples; the final SIGALRM is the timeout.

The preceding Riemannian declarations at original lines 25,505,940,
25,512,959, and 25,525,774 had repeated dependency-traversal/GC samples.
The earlier shared-reduction attempt `20260913T221945541382Z` had passed these
declarations and `spineEquiv`. Absence of samples is not an exact timing.

The previous Lie repair forced the difficult second typed comparison into an
unbounded non-sharing attempt. That repairs loss of a common symbolic head in
the Lie theorem, but can repeat substantial reduction and inspection on other
inputs. Neither universally enabling nor universally disabling destructive
sharing is a satisfactory performance policy for these observed workloads.

## Scope of this change

Only `kernel/conversion.ml` changes in the kernel for this pass. The old source
is preserved as Git blob `fe6c874a2f7f60507aa06515627e6cee726bb3ae` in the kernel
worktree; it includes all earlier work and is NOT the repository HEAD.

After the existing cheap 256-step attempt, the difficult typed conversion:

1. Tries shared reduction with a 4096-conversion-step allowance.
2. If needed, tries symbolic preservation with the same allowance.
3. Doubles the allowance for modes that exhausted it and retries from the
   original terms, checked universe state, fresh closures, and local caches.

A completed negative mode is retired. A positive result must come from an
actual completed kernel comparison. Errors and interrupts propagate. Exhaustion
is not equality or a negative conversion result. Integer saturation retains an
unbounded fallback without overflow. An explicitly non-sharing caller does not
run two identical modes.

These are conversion-step allowances, not wall-time or individual WHNF-step
limits. The scheduling test's geometric overhead bound concerns its synthetic
work model only. This is not a wall-time guarantee or a proof that all future
declarations will avoid timeout. The other existing conversion fallbacks remain.

No importer, foundation, checking flag, universe constraint, transparency rule,
registration, equality rule, or checkpoint representation is weakened/changed.

## Reproducibility and validation

Candidate worker: `3adbcb1ad9ff02a21a404581f6bc902d7107fc7d799f1c9f8bb067b3f291e0a7`.
Checker: `ea0103942bd4bafbaa6f9a8b61ef9f9d728a72320c1c8d6917e0bffc8d18cd4a`.
Conversion source: `549ec339bacf204d3f5fd13670447dd072a3cee9b3030bde2f93020be110e7ab`.

- `test-candidate.sh`: private runtime tests pass, including scheduling both
  winning modes, retiring failed modes, exception propagation and saturation.
  The scheduler test is also integrated into the main alignment gate.
- `../mathlib-lie-trace-repro/proof-balanced-sharing/result.json`: the earlier
  Lie proof passes on the candidate in 70.58 seconds including load/save. Its
  dependency prefix retains all proofs and was separately compiled previously.
- `slice.json`: combined regression slice, 3,083,816 selected NDJSON records,
  **zero abstracted proofs**, original dependency order, pinned source/exporter.
  `CombinedTargets.v` times the four reported declarations separately with a
  120-second per-line timeout. The prefix is compiled separately from line 1.

Pending: combined replay, broad native/importer/checkpoint regression gates,
independent target checks, and strict native checks. The independent target
checker deliberately reuses the separately typechecked dependency prefix;
it does not independently recheck all dependency modules. Strict native checks
are separate from the unchanged importer compatibility profile.

The last sealed production checkpoint is 25M. A successful candidate can resume
at 25,000,001 without deleting or rewriting its producer seals. Full Mathlib
verification remains incomplete until the corpus run reaches EOF.
