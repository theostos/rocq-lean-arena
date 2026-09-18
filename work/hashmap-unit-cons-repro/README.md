# Direct unfolding dependencies

**Follow-up:** the resumed full run passed this theorem, then failed at
`Int32.minValue_div_neg_one`. The launcher now includes [that correction](../int32-min-div-repro/README.md)
too; the hashes below document the direct-dependency-only worker.

The full cslib run timed out after 600 seconds at line **12,923,688**:
`Std.HashMap.unitOfList_cons`. Memory stayed near 9.4 GiB, below the 16 GiB
limit. This was a conversion timeout, not an out-of-memory failure.

## Cause and fix

The proof applies the HashMap extensionality lemma to
`Std.DHashMap.Const.unitOfList_cons`. Conversion must unfold a HashMap wrapper
to expose the corresponding DHashMap operation.

The experimental dependency probe recognized constants whose bodies depend
on the target, but explicitly excluded an occurrence of the target itself.
Consequently it missed this direct dependency and unfolded the DHashMap
operation, entering large comparisons of its implementation.

The fix is in `kernel/conversion.ml`: a constant is a dependency witness if
it **is** the target **or** its body depends on it. The existing probe budget,
closure inspection and fallback remain unchanged. This only changes which
side conversion unfolds; the resulting terms are still compared normally.
No importer change, new axiom, library proof rewrite or increased timeout.

Local review branch: `fix/direct-unfolding-dependency`, based on
`review/conversion-strategies` (commit `eb0b398bbf`). The experimental worktree also has
the same correction. The review branch is not yet published.

## Reproduction

`export.sh` exports the unchanged theorem and dependencies from the installed
Lean 4.27.0-rc1 Std library. `HashMapCons.lean-export` has **165,051 lines**.
The last line is the target declaration; `Prefix.v` saves everything before it.

All runs use the shared memory guard and atomic checkpoint runner. The small
reproduction is capped at 2 GiB with a 6 GiB system reserve. Jobs run sequentially.

```sh
bash work/hashmap-unit-cons-repro/run.sh Prefix UNIQUE_TAG
bash work/hashmap-unit-cons-repro/run.sh Target UNIQUE_TAG
bash work/hashmap-unit-cons-repro/run.sh Reload UNIQUE_TAG
```

Evidence retained in this directory:

- `Target.baseline.*`: the original worker times out at the target after 30s.
- `Target.entries.*` / `Target.trace.*`: translation finishes; conversion call
  227 expands into over a million comparison steps before the timeout.
  Pair-retaining diagnostics were not enabled.
- `Target.direct-dependency.*`: the same conversion succeeds; the process
  reaches the end of the import at 1.84 CPU seconds. The unchanged theorem
  also passes without diagnostics (`Target.direct-dependency-regressions.*`).
- `Fresh.direct-dependency-regressions.*`: a fresh import checks all 2,032
  entries, with a 30s per-declaration timeout.
- `Reload.direct-dependency-regressions.*`: the saved target reloads and
  reports its assumptions.
- `DirectDependency.baseline.*` / `DirectDependency.candidate2.*`: the small
  Rocq-only regression times out at 5s before the fix and passes afterwards,
  in both comparison directions. It also rejects an unequal pair. Its
  `exact_no_check` leaves proof validation to the ordinary kernel at `Qed`.

`run-regressions.sh` also checks the previous ModifyEq, LinearMap, FinLoop and
Int32 reproductions, the unit/arithmetic controls and ten importer fixtures.
All 20 checks pass with tag `direct-dependency-regressions`. It does not run
the full cslib continuation.

`../unit-projection-repro/check-prefix.sh direct-dependency` loads the original
11-million-line prefix and saves a dependent module successfully. All pinned
historical inputs still match. This checks checkpoint compatibility, not fresh
verification of the prefix's proofs.

## Resume the full run

The existing launcher now pins the corrected worker. The original prefix and
input manifests are preserved; no library-digest bypass is enabled.

```sh
bash work/unit-projection-repro/resume-cslib.sh
```

This resumes from the saved checkpoint at **11,005,951**, not the failed line
12,923,688. Limits remain 16 GiB hard / 15 GiB RSS / 3 GiB system reserve, with
one worker. No full continuation was launched as part of this fix. Passing the
isolated reproduction does not establish full-context or full-library success.

## Artifact hashes

```text
baseline worker: 8c924251187f15b14a529758a8b1e67d6fd48ac691b69539699c14e2c3a41bb1
patched worker:  829aff8548eb3d9f614130de284a1f659411929a404ec2375c85cb4daef612c5
export:          7f01a3ea2c9cf5affcdcff5009e312a6ef331a7fdb0564e3ac0d2db3d9f567b0
```

The modified kernel and inherited importer trust boundary still require
expert review; these checks are not a soundness certification.
