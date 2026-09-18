# Mathlib 13M: a unit-like value inside a record

The resumed Mathlib run passed and freshly reloaded the 12M and 13M
checkpoints, then failed at NDJSON line **13,061,816**:
`CategoryTheory.Functor.punitExt._proof_3`.
The exit code was **1** (a conversion rejection), not a timeout or memory stop.
The original log is
`../mathlib-ndjson/attempts/20260911T072304084029Z/MathlibTo14000000.run.log`.

## Cause

The exported proof uses reflexivity for an equality between two compositions
in the discrete category on `PUnit`. Its morphism type is
`ULift (PLift (X.as = Y.as))`.

`PLift` of an `SProp` proof is already registered as unit-like: its only field
is irrelevant. `ULift` is an ordinary primitive record with eta conversion.
Consequently, at this instantiation its only field is itself unit-like.
The object type `Discrete PUnit` has the same wrapper pattern.
The previous recognition code only recognized the directly registered type,
not such an instantiated wrapper. Conversion therefore tried to distinguish
two neutral computations producing wrapped proofs and rejected reflexivity.
`id_inst1` is the context exposing that mismatch, not the faulty definition.

## Repair

The change is confined to `kernel/conversion.ml`, with the regression
`test-suite/success/unit_like_record.v`. The transitive dependency bitset cache
in `kernel/environ.ml` is unchanged. `kernel-fix.patch` contains the isolated
source delta and new regression, preserving the pre-existing worktree edits.

The existing type-only unit query now also recognizes a primitive record
whose instantiated field types are all irrelevant or recursively unit-like.
This is derived from the existing record-eta and registered unit rules; it
does not globally register `ULift`, and does not identify `ULift nat` values.

The query has a 32-node nontrivial-type budget, a separate reduction table,
and only beta/zeta reduction in its added field traversal. It does not inspect
record values, unfold opaque aliases, or classify scrutinee-dependent fields
using a dummy record. Plain single-constructor inductives without record eta
are excluded.

Proof bodies, importer binaries, export, serialized format, resource limits,
and the existing canonical checkpoint sources and seals are unchanged.
These are checks of the experimental kernel, not a stock-Rocq validation or
a general soundness certification.

## Evidence

- `Prefix-rsj3ca37/`: every declaration from 13M to immediately before the
  failure checked and saved under the previous worker.
- `Target-ejr413aa/`: the same illegal application reproduced from that
  prefix. Conversion calls 219–222 reject it through all four fallback modes.
- `Target-aihsghm8/`: trace of the final comparison, call 222.
- `InspectLifts-dknoivg6/`: the actual imported `ULift`/`PLift` declarations
  and a failing small wrapped-proof comparison.
- `WrappedUnit-mhpq581n/`: standalone baseline rejection at `Qed`, without
  the importer. `WrappedUnit-qqvzs4h8/`: the candidate passes, including
  nested wrappers and negative controls.
- `unit_like_record-hyr5jhjo/`: expanded kernel regressions pass, including
  applied projections, genuine opaque values, ordinary data, unknown type
  parameters, dependent fields, non-record inductives, and opaque aliases.
- `Target-k14r715x/`: the original failing theorem checks and saves under
  the candidate; its kernel declaration check takes about 0.004 CPU seconds.
  The full load/check/save takes 235.05 seconds.

`Target-6z1twsgh/` deliberately stops to print the translated proof before
checking; its nonzero result is diagnostic, not another kernel rejection.
`UnitAlias-*` explores a separate conservative limit on applied type aliases;
that limit is not changed by this repair.

The old worker is retained as `rocqworker.baseline.exe` (SHA-256
`f8b61efc2d7c33f61f794be5f81d6a0d0f78c2f60ddcd64f43776f6f5212518a`).
The candidate worker is SHA-256
`a391359995f9406156307448b6356d4ff5e80b28f053850b6ae95632d8c5e78e`.
`conversion.baseline.ml` preserves the exact pre-repair source, including
existing user changes.

## Final validation and resumption

Validation completed successfully in `validation-5vf9k2ko/`. All gates passed:

1. The new positive/negative kernel regression.
2. An eager 13M–13,061,816 replay preserving `MathlibTo14000000` and the
   original declaration order, followed by successful saving.
3. A fresh process loading that artifact, unpacking the importer state and
   re-saving it.
4. The existing 20 focused kernel tests, 44 importer/CSLib fixtures, and
   runner test suite (201 tests, 2 skipped).

The original-sequence replay and save took **267.65 seconds**, with
**4.62 GiB** peak cgroup memory. Fresh loading, unpacking and re-saving took
**249.38 seconds**, with **4.58 GiB** peak. Artifact hashes and the exact
tested worker/source hashes are recorded in `full/result.json`,
`reload/result.json`, and `passed.json` under that validation directory.

All 13 canonical checkpoints verified again after validation; see
`verified-checkpoints.json`. Only the explicit, approved worker migration
differs from their producer inputs. The export, importer inputs, checkpoint
sources and original seals were not changed.

The resume helper refuses to launch until every gate has passed, the tested
worker and sources match, and the saved replay/reload artifact hashes match:

```sh
bash work/mathlib-punit-ext-repro/resume.sh --check
bash work/mathlib-punit-ext-repro/resume.sh
```

It uses the existing runner and checkpoint migration verification, with
1,800 seconds per declaration, one worker, a 16 GiB/no-swap cgroup, the
existing RSS guard, and the disk-space reserve. It does not modify old seals.
After validation, the user-authorized continuation was started as the
background service `rocq-mathlib-ndjson-wrapped-unit.service`, resuming from
13M. Its supervisor log is
`../mathlib-ndjson/wrapped-unit-resume.supervisor.log`.

```sh
python3 scripts/mathlib_ndjson_loop.py status
```
