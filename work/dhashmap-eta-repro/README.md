# DHashMap regression from broad delta-before-eta priority

The `eta-review` validation failed inside `hashmap-unit-cons-repro/Fresh.v`:

```text
Error at line 164989 (for Std.DHashMap.Const.unitOfList_cons):
#HINT_OPAQUE 14500 148234 148355 5
Lean import line timed out.
```

This is the 30-second declaration timeout, not a universe error or memory
failure. The full CSLib import was never reached. It is a dependency of the
HashMap theorem, distinct from the earlier timeout on `Std.HashMap.unitOfList_cons`.

## Cause and repair

The preceding Int8 repair made delta reduction precede general record eta.
That fixed `Int8.toBitVec_not`, but regressed this DHashMap proof. In conversion
call 235, `Raw₀.insertIfNew` is compared with a subtype constructor. Eagerly
unfolding it expands the hash-map implementation into a large stuck elimination;
conversion then compares its internal computations instead of matching the
record's projections. The scalar trace records over a million comparison steps.

The corrected strategy preserves early record eta and extends the existing
constructor-wrapper exception to syntactic projection wrappers. Only transparent
constant bodies whose lambda/application head is a constructor or projection
(following up to 32 transparent head aliases), with an application-only stack,
receive this unfolding preference. This keeps
the Int8 projection wrapper reducible before eta while preserving DHashMap's
early eta path. All exposed terms still undergo ordinary kernel conversion.

The importer, original Lean proofs, universe constraints, line timeout and
memory limits are unchanged. This is a repair to the experimental kernel's
conversion strategy. It does not establish full CSLib acceptance or certify
the soundness of the inherited experimental kernel.

## Controlled evidence

`HashMapCons.lean-export` links to the unchanged 165,051-line dependency export.
`Prefix.v` freshly checks lines before 164989; `Target.v` checks the remaining
declarations. The end-exclusive boundary omits no declarations between them.
Both use the foundation freshly built for the user's `eta-review` run.

| Worker / check | Result | Logs |
| --- | --- | --- |
| User's broad-eta worker, isolated target | Timeout on DHashMap, conversion 235 | `Target.entries.*`, `Target.trace2.*` |
| Saved worker from before the Int8 repair, same target | Pass through HashMap | `Target.pre-int8.*` |
| Narrowed wrapper preference, same target | Pass through HashMap | `Target.aliases.*` |
| Narrowed wrapper preference, fresh Int8 import | Pass | `../int8-conversion-repro/dhashmap-candidate/` |
| User's broad-eta worker, standalone regression | First `Timeout 5 Qed` fails | `EtaBeforeComputation.baseline.*` |
| Corrected worker, standalone regression | Both directions pass; unequal-field controls rejected | `EtaBeforeComputation.aliases.*` |

The standalone test checks eta against an expensive record producer. Its
initial draft accidentally evaluated a closed scrutinee while defining the
producer; that diagnostic attempt was interrupted and is recorded in
`EtaBeforeComputation.candidate.*`. The retained test parameterizes the fuel,
so the regression exercises conversion at `Qed`, as its baseline error shows.
`Target.trace.*` was refused by the shared guard while the preceding diagnostic
still owned it; no second worker started. The successful retry is `trace2`.

The direct-projection-only candidate passed DHashMap and Int8, but the
`eta-review-fixed` gate caught the named-projection case in `Int32.toBitVec_not`.
The final worker also follows transparent head aliases. The isolated adjacent
export then passes through all remaining integer theorems (`AdjacentTarget.aliases.*`).
`ProjectionAliases.before-alias.*` times out with the direct-only worker; the
final worker passes both directions and rejects opaque aliases (`ProjectionAliases.aliases.*`).

The complete fresh regression gate is run by:

```sh
bash work/int8-conversion-repro/check-and-run.sh eta-review-fixed2
```

This tag is already used. Its log is `check-and-run-final.log`, with staged tests in
`../int8-conversion-repro/eta-review-fixed2-regressions/`. Only after the complete
gate succeeds does the command launch full CSLib from line 1. Use a new tag
for any later rerun. All heavyweight jobs use the shared memory guard.

## Validation result (2026-09-08)

The `eta-review-fixed2` gate passed **41 compiler checks**, including the full
fresh HashMap dependency import, both new regression fixtures, and all ten
importer fixtures. The Python suite passed 185 tests (2 skipped). Input hashes
and the tested worker identity were verified before the gate recorded success.
See `verification.json` and
`../int8-conversion-repro/eta-review-fixed2-regressions/passed.json`.

The command then started a fresh full CSLib run in
`work/cslib-from-start/20260908T132914665228Z/`, from line 1. At handoff it is
running; full acceptance remains unverified. The validator now includes the
compiler error and log paths when a check fails, without retrying type errors.

## Artifacts

`conversion.ml.before` and `rocqworker.baseline.exe` preserve the user's failing
worker. `baseline-hashes.json` and `final-hashes.json` identify the actual inputs.
`kernel-change.patch` isolates this repair on top of that worker's source;
`../int8-conversion-repro/kernel-change.patch` contains the combined, narrowed
Int8 repair and four kernel regression fixtures. Both reverse-apply checks pass.
The superseded broad Int8 patch is retained as `int8-broad-eta.patch`.

```text
failing worker: 7e36a7cb1c1921b93ed0c7124364fa0a16a9f0a787f060c448522bb37d161c34
fixed worker:   5285fe33bb678eccdc41fd6de1ad09eed93bd8df243b0a3df1581de35f1ce578
fixed source:   b90b927b71d9ce83cd86e10844cf5fa334c8e254e30ae61a4a82bfaab3e1e750
export:         7f01a3ea2c9cf5affcdcff5009e312a6ef331a7fdb0564e3ac0d2db3d9f567b0
```
