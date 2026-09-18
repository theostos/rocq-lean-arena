# Char successor conversion: investigation and validation

Current candidate: [DECLARED-ORDER-CONTINUATION.md](DECLARED-ORDER-CONTINUATION.md).
The v13 pipeline is testing direct-witness-before-hint ordering on top of the
private type-query change. V12 was rejected by a legacy regression.
Check `validation-v13/progress.json` and `finish-status.json`.

Latest continuation (2026-09-15): batch v10 passed its first 12 stages,
including uninterrupted original-order Char replay and independent checking,
then hit the 120-second Riemannian declaration timeout at 25,505,940. A new
demand-driven private type-query candidate also timed out there in v11.
See [TYPE-QUERY-CONTINUATION.md](TYPE-QUERY-CONTINUATION.md) for the current
implementation, binary identities, and evidence. Current progress is
`validation-v11/progress.json`; supervisor state is `finish-status.json`.
The historical candidate results below are not qualification of the new worker.
The supervisor stopped without a production restart. A prepared-prefix
diagnostic is collecting conversion timings; production remains gated on all
18 validation stages succeeding on a corrected candidate.

## Earlier Char candidate and resource continuation

Status (2026-09-15): the private call-by-need implementation passes the complete
Char slice (100.22s), including the successor and earlier ordinal regressions,
and independent checking of that slice (19.81s). All 32 focused tests and the
native unfolding fixture pass. Broad validation is still required before
production resumes. The guarded supervisor queues that validation until the
required memory allowance is available and resumes only after all checks pass.

Resource continuation (2026-09-15): the prior batch `validation-v9` stopped
with exit75 at the previous-Char stage: only18.49GiB was available at the
guard's final admission check, below the19GiB requirement. No compiler started
for that stage, so this was not a kernel failure. Its evidence is preserved.
`validation-v10` uses a1GiB cap for the native alias fixture and8GiB for the
two Char slices. Large original-order replays retain the16GiB hard/no-swap cap
and3GiB reserve (19GiB required, within the user's20GiB allowance).
Each stage waits for its own allowance. A verified pre-launch memory refusal
can be requeued, preserving the refused attempt; a started proof check, timeout,
OOM, or proof failure is never retried automatically. The queue and supervisor
have17 passing control-flow tests. No kernel heuristic changed for this resource
continuation, and unrelated Lean experiments are left untouched.

Historical progress: `validation-v10/progress.json`; supervisor state:
`finish-status.json`; service output: `validation-service.log`.

## Reproduction

The reported failure is at original line 30,778,865,
`_private.Init.Data.Char.Ordinal0.Char.succ__q._proof_1`.
The previously repaired ordinal proof at 30,805,408 must remain working.

The crashed worker was preserved as `baseline-worker.exe`, SHA256
`80c4781a4738d0509f88630d70583415a93b8d88a1f15306561fd88c70e70940`.
Its uninterrupted replay under the production module name
`MathlibTo35000000`, starting from the sealed 30M checkpoint, timed out on
the reported successor proof at the 120-second declaration limit.
Evidence: `production-order-baseline/result.json` and `run.log`.

Both an extracted successor proof and a replay after saving/reloading the
immediate diagnostic prefix passed on that same old worker. Those isolated
successes are therefore not sufficient evidence of a fix. The final gate
includes the uninterrupted production-order segment through line 30,806,240,
covering both failure points and the enclosing ordinal theorem.

The separate native test `FixPriority.v` exposed a concrete scheduling defect:
`costly 26 = wrapper 26`, where `wrapper n := costly n`, timed out although
unfolding the alias exposes the same symbolic call. Traces identified two
stages of needless work:

1. Constructor-driven recursive evaluation could take precedence over the alias.
2. Once both heads matched, the same-head eliminator preference suppressed
   argument congruence, including arguments differing only in representation:
   exposed `FConstruct` versus delayed `FCLOS(App(Construct, ...))`.

## Relation to Lean

The comparison uses Lean 4.29 commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740`, with a local reference copy in
`../mathlib-riemann-sharing-repro/lean-4.29-reference/`.

[Lean's type checker](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp)
performs quick equality checks around reduction and uses same-definition
argument congruence for regular hints. Primitive recursor reduction and
ordinary definition unfolding are distinct there. The Rocq translation wraps
recursors in ordinary definitions, so scheduling must preserve their useful
constructor-driven behavior without forcing an already-reflexive computation.

This is a targeted adaptation, not a claim that the two kernels now have
identical evaluation strategies or that every remaining Mathlib issue is fixed.

## Current candidate

Changes for this continuation are in `kernel/conversion.ml` and
`kernel/cClosure.ml` / `.mli` (on top of the prior alignment work):

- A bounded direct-head-alias observation can prefer exposing the alias over
  evaluating the recursive call it wraps. Both references must already be
  unfoldable; opacity and reduction flags are not bypassed.
- Same-head constructor-driven elimination first permits ordinary congruence
  when a read-only argument probe recognizes identical syntax. The probe
  handles split application frames, suffix shifts, regular substitutions and
  mixed constructor views, including nested constructor/application/shift forms.
- Successful observation does not accept equality itself. Existing head,
  universe, relevance and complete-stack checks remain responsible for that.
- The pre-existing fast comparator charges lambda binder lists before
  reconstructing their syntax. Budget exhaustion remains inconclusive.
- Recursor majors are reduced with ordinary weak-head reduction in a private
  call-by-need view, without a demand-step cutoff. Successful constructor
  results replace only that argument in a copied stack frame. Merely observing
  the constructor was insufficient: subsequent unfolding reused the projection
  and compared discarded Fix/Case branches. The reduced root is now carried
  into ordinary iota conversion; no equality judgment is accepted by the probe.

The syntax-identity observation remains a bounded scheduling hint. In contrast,
the demanded-major reduction is not a bounded speculation: it computes the
argument needed to select the next branch, just as Lean's `reduce_recursor`
requests `whnf(major)`. A failed demand leaves the original symbolic term intact.
See also [Lean's recursor reduction](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/inductive.h#L68).

Rocq's ordinary reducer updates shared closure cells. Doing that directly on
the original major regressed `Int.Linear.eq_of_core`: a failed demand exposed
large recursive bodies subsequently compared by congruence. Non-sharing
reduction avoided this regression and passed the Char slice in 105.23s, but
duplicated shared let computations (depth8/16: 243472/62390032 allocated bytes).

The current reduction view maps a visited original cell to a private owned
cell. Reduction updates and repeated demands reuse the owned cell. Syntax,
arrays and substitution environments are borrowed, not eagerly traversed;
their contained cells are copied only when demanded by the head machine.
The same shared-let test now allocates 10048/18880 bytes at depths8/16.
This adapts immutable input preservation and memoized evaluation to Rocq's
mutable closure representation, without adding an equality rule. The view
lives only for one demanded-major computation. It is not a dependency cache.

Restricting the earlier cross-head preference to nonrecursive Case bodies was
tested and rejected: it regressed the old ordinal proof. Failed candidates and
their evidence are retained in `validation/`, `validation-v2/`, and
`validation-v3/`. The current candidate retains both Fix and Case preference.

## Validation scope

Current private-demand worker:
`befbefc96a53a9176abbe8acfa35f7318fa8cdaa88e6c8c9cdb6475171fe8e16`.
32/32 focused tests and the existing closure suite pass. The native unfolding
fixture passed in0.56s. ABI-compatible core plugins and identical-source
`importer.k9WSHRtn` were rebuilt before proof replay.
`whole-demanded-private/result.json` records the100.22s replay;
`whole-demanded-private/independent.json` records the19.81s independent check.
The current candidate must still pass the uninterrupted original-order replay
and the broad regression gate. The successful non-sharing experiment is not
its validation certificate.

For candidate5, the full native unfolding fixture and private unit tests passed before starting
the serial gate. Tests include both alias directions, discarded expensive
branches, unequal results, opacity, neutral majors, shifts, substitutions,
constructor identities/arity, mixed representations, exhausted budgets and
non-mutation checks. The previous ordinal replay passed again.

The prepared 18-stage gate has not completed for this candidate: Char slices and original
order, independent checking, SSet/Lie/derivative/Riemannian regressions, native,
legacy, importer, runner/checkpoint/resource and strict-policy checks.
`passed.json` is written only after all stages succeed on unchanged pinned
inputs. `resume.py` separately checks that evidence before launching anything.
`finish.py` performs that sequence without model supervision and makes one
startup observation only. Its seven control-flow tests pass, including refusal
to launch after failed validation or promotion. It retains the16GiB allowance
and3GiB reserve; it does not stop unrelated Lean REPL jobs. Status is recorded
in `finish-status.json`, and the complete service log in `validation-service.log`.

Independent continuation checks recheck the new module while explicitly reusing
its already sealed dependencies (`-norec`). They do not independently recheck
all earlier Mathlib. The combined Char slice retains every extracted proof,
with zero abstractions.

## Production boundary

Resume only after successful validation, from the unchanged sealed 30M
checkpoint in `work/mathlib-alignment-5m-20260913-with-terminal`.
Keep checkpoints every 5M lines, the existing 1800-second declaration bound,
16GiB/no-swap guard, importer and checking policy unchanged. Do not rewrite
producer seals or launch a second worker alongside a running production service.

Full Mathlib verification remains incomplete until the 100,001,405-record
stream reaches EOF. After a validated restart and startup check, leave the
production loop detached without assistant monitoring, as requested.
