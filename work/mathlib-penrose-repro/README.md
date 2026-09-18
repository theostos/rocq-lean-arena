# Penrose literal repair — 2026-09-18

Target: original NDJSON line **58,521,284**, `_private.ProofWidgets.Component.PenroseDiagram.0.ProofWidgets.Penrose.Diagram._proof_1`.

This is a reflexivity proof mentioning an embedded widget string of 2,786,515
characters. The serial importer expands that literal to a list of reflected
characters. The original production worker eventually received SIGSEGV while
processing this declaration. Its last successful sealed checkpoint is 55M.

## Diagnosis and repair

Changes relative to kernel handoff snapshot
`d17b66af824e344393b126e57fbcec99174f926a` affect four kernel files and the
standalone checker's serialized-value validator and typed comparison entry point:

| File | Problem | Repair |
| --- | --- | --- |
| `kernel/hConstr.ml` | A shallow generic hash gives deep list nodes identical cache hashes; chained physical-identity lookups become quadratic. Recursive application traversal then exhausts the OCaml stack once the lookup bottleneck is removed. | Partition physical memo keys by application traversal depth, retaining all completed entries rather than evicting colliding shared subterms. Application continuations move to an explicit heap worklist. The context-sensitive canonical table and exact equality remain unchanged. |
| `kernel/vars.ml` | The universe collector repeats the same collision-chain and recursive-traversal problem. | Iterative universe collection with depth-partitioned physical memoization; cache entries are installed **after** visiting children. Quality/universe set operations are unchanged. |
| `kernel/typeops.ml` | Application inference recursively descends the literal list. Also, the conversion-cache shallow hash misses the differing literal beneath the common reflected-character type prefix, continually evicting completed comparisons. | Iterative application inference preserves argument-first checking and template-polymorphic head handling. Conversion keys fingerprint the complete syntax within the **existing** 1024-node inspection bound; larger terms bypass this optional cache. Exact comparison, environment identity, direction, failure handling and ordinary conversion fallback are unchanged. |
| `kernel/constr.ml` | Canonical hash-consing recursively descends the same list. | An application worklist preserves the original hash combination, smart array reuse, reference-count policy and canonical tables. |
| `checker/validate.ml` | The standalone checker overflowed its stack while validating the saved object's shape, before theorem checking. | Field continuations move to a heap worklist. Object/validator memoization, field order, rejection rules, error contexts and existing cycle policy are preserved. |
| `checker/mod_checking.ml` | Its final comparison went directly to conversion, bypassing the new exact-syntax shortcut in Typeops. | Use `Typeops.check_cast` on the independently inferred body and declared-type judgments, matching the worker's checked comparison. |

The physical memo bypass for atomic nodes explicitly counts repeated canonical
global heads, preserving their eligibility for inference caching. This was
caught in the final refcount audit after the first successful full-sized replay.

No reduction or typing rule is added. No check is replaced by a hash comparison.
There is no raw OCaml pointer hashing (moving GC would invalidate it). No term
representation, `.vo` format, importer source, resource limit or proof-skipping
policy changes. In particular, the 1800-second declaration timeout is unchanged.

A final, separate problem was hidden behind those traversals: after inference,
the bounded syntactic equality shortcut gave up on the two copies of the large
reflexive type, sending conversion into computation of the widget's string
hash. Typeops now distinguishes a structural mismatch from exhausted inspection.
On exhaustion, under the existing import-alignment flag, it interns the two
already-checked types together using HConstr's existing strict/context-sensitive
equality. Only identical resulting nodes certify equality; otherwise ordinary
conversion runs. Application and default-cast checks use this path. Native/VM
casts and conversion's unfolding rules are unchanged.

The fresh-ID 3,000-character reproducer spent 124.08 CPU seconds before checkpoint
serialization before this last fix, versus 1.90 seconds afterward. Its type/body
checking took under one second in both runs; the difference was the final cast.

The partially repaired diagnostic replay reached 400,000 application comparisons
at 180.34 CPU seconds, with only 278,548 cache hits. Samples showed reflected
character validity types repeatedly being reduced against `Char`. That is why
fixing just the first reported stack was insufficient.

## Lean comparison

At the export's pinned Lean revision, expression nodes carry their hashes and
the expression cache overwrites colliding slots, verifying exact equality on
lookup: [expr.h](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/expr.h),
[expr_cache.cpp](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/expr_cache.cpp).
Lean also represents string literals compactly. This is not a literal port of
Lean's cache: overwriting collisions with Rocq's shallow runtime hashes caused
exponential re-traversal of crossed DAGs in an initial candidate, caught by a
regression test before release. The replacement retains entries, partitions
keys by traversal depth and still verifies exact identity/context. It makes
the long-list traversal practical without that eviction regression. It does
not promise linear behavior on every DAG: a node reached at multiple depths
can still be visited once per depth. The imported character-list representation
still requires work proportional to this very large literal.

## Reproduction and evidence

`prepare.py` retains every dependency proof (zero abstracted proofs) in a 9,940
record slice. `slice.json` binds the source export and extraction. The native
NDJSON reader expects consecutive IDs, so the sparse slice is converted using
the existing arena converter; `legacy.json` binds both streams and the converter.
The legacy target is record 9,939. This changes IDs/serialization, not the proof.

`baseline-prefix-legacy` contains the dependency prefix checked by the production
worker. `candidate-target-7` is the final exact target replay using the rebuilt
serial importer `importer.m63OyviU`. `candidate-target-6` is the earlier successful
compiler replay, before the checker-load and atomic-reference-count repairs.
`check.py` independently checks the target `.vo`
with `rocqchk -norec`: it reuses the separately compiled prefix/foundation, and
does **not** claim a recursive standalone recheck of all dependencies.
`final-validate.py` waits for the saved target's check with the final checker,
verifies that evidence, then runs the final compiler replay. If the two target artifacts have identical
SHA-256 hashes, `standalone-evidence.json` explicitly records reuse of that
check; otherwise it runs a fresh check on the final artifact. It never relabels
the actual earlier checker invocation as a new execution.

`units.py` records ten focused native test groups, including three-million-node
hash-consing/universe/canonical traversals, shared DAGs, context separation,
GC compaction, exact-syntax differential tests, canonical hash compatibility,
negative conversion tests, substitution/lifting and existing conversion units.
The standalone validator is compared against the saved baseline on 272 valid/
invalid shape combinations, including exact first-error contexts, plus shared
objects checked with distinct validators and the pre-existing cycle policy.
`candidate-units-3` is the final native qualification directory.
`focused.py` checks 18 `.v` fixtures, including prior unit-like/projection/eta
repairs, conversion-cache rejection cases and template polymorphism. The prior
Padic failure is replayed separately in `../mathlib-padic-repro/penrose-regression-2`.

Historical failed/interrupted attempts remain available:

- `baseline-prefix`: sparse-ID NDJSON reader failure, not a kernel regression.
- `deep-2.log`: original recursive traversal stack overflow after fixing caching.
- `candidate-target-1`: stopped after diagnosing the universe collector.
- `candidate-target-2`: stopped after diagnosing repeated character conversions.
- `candidate-target-3`: stopped after isolating the final reflexive cast.
- `candidate-target-4`: stopped before qualification when the crossed-DAG test
  exposed the collision-eviction regression in that candidate. `cross-dag-7.log`
  records it; `cross-dag-9.log` tests the replacement through depth 256.
- `candidate-target-5`: the memory guard refused overlapping execution with
  the deep traversal stress test (exit 75); no theorem checking started.
- `candidate-target-6/independent`: the first standalone check failed with a
  stack overflow during serialized-value validation, before checking a single
  declaration. This exposed the additional checker traversal repair above.
- `candidate-target-6/independent-2`: loaded successfully after the validator
  repair, then was stopped to make the checker's final typed comparison use
  the same entry point as the worker. It is not a completed validation.
- `candidate-units`: the aggregate three-traversal stress test hit its initial
  90-second harness bound on a repeat. `deep-10.log` had completed the same
  three traversals in 88.50 CPU seconds. The test-only wall-clock bound is now
  120 seconds to leave scheduling margin; `candidate-units-2` records the rerun.
  This does not change any production or proof-replay timeout/resource limit.
- `diagnostic-target`: temporary instrumentation run, never a release worker.
- `small-3000`: discarded diagnostic that reused the original literal from the
  prefix's expression cache. `fresh-small-3000` and `fresh-small-3000-fixed`
correctly use fresh expression IDs and provide the reduced before/after test.

The earlier full-sized target replay `candidate-target-6` completed with
exit code 0 in **680.28 wall seconds**, including load/checkpoint/save, using
worker `a32c95df9b5b8f79b289d372e8b33bccbc8fb443f7421e3e73d4a7a90a29412c`.
The pre-checkpoint CPU reading was 652.31 seconds; the guarded scope peaked at
3,898,832 KiB (about 3.72 GiB), within the unchanged 16 GiB validation cap and
1800-second declaration timeout. The original production failure did not
complete, so this is not a measured baseline speedup ratio.

The final worker replay `candidate-target-7` completed with exit code 0 in
**660.31 wall seconds**, including load/checkpoint/save. Its pre-checkpoint CPU
reading was 635.67 seconds. Worker SHA-256:
`a0aa7234b01883d29dcc51bc6b99e14065df4aa9dbff3d194e225f5fb1757983`.
Final target artifact SHA-256:
`904a750fd234fe6b5db9888a367b9bf1a999dea880a39fea526559f9c62ae00b`.
The guarded replay's peak was 3,893,420 KiB (about 3.71 GiB).
This differs from the earlier artifact; therefore the final qualification
used a fresh standalone check, not reuse of the earlier successful check.
That earlier check (`candidate-target-6/independent-3.json`) passed in 562.39
wall seconds with the final checker, but applies to the earlier artifact only.

The final artifact's standalone check (`candidate-target-7/independent.json`)
passed in approximately **588 wall seconds**, peaking at 2,782,384 KiB (about
2.65 GiB). `standalone-evidence.json` records `fresh-check`. This checked the
target proof independently while reusing the compiled dependency prefix;
it was not a recursive standalone recheck of all Mathlib.

The final worker also passed all ten native groups (`candidate-units-3`) and
all 18 focused fixtures (`candidate-focused-2`, 11.19 wall seconds). The combined
three-million-node traversal test finished in 92.17 wall seconds, peaking at
2,107,932 KiB. The prior Padic proof replay (`penrose-regression-2`) passed in
60.48 wall seconds including load/checkpoint/save. These are completed final
worker results, not earlier candidate results.

Final results are the machine-readable `result.json` files and
`validation-receipt.json`; absence of the receipt means qualification is not
complete. Passing this focused qualification is not proof that all Mathlib or
the entire Rocq regression suite passes.

## Continuation

`resume.py release` verifies completed results, exact binary/source hashes, the
unchanged 55M seal and resource policy before starting
`rocq-mathlib-penrose-25gb.service`. It creates a new consumer certificate without
editing old producer seals. The loop remains serial, checks every proof,
checkpoints every 5M lines and uses the previously authorized 25 decimal GB cap,
2 GiB host reserve and no workload swap.

Progress: `journalctl --user -fu rocq-mathlib-penrose-25gb.service` and the latest
`../mathlib-alignment-5m-20260913-with-terminal/attempts/*/MathlibTo60000000.run.log`.
No checkpoints have been deleted for this repair. No remote files or published
handoff branches have been changed; this repair is local until explicitly synced.
