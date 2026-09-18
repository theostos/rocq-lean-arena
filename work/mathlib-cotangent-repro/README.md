# Cotangent timeout, 2026-09-17

Production stopped at NDJSON record **45,934,611**, the private theorem
`Algebra.Generators.PresentationOfFreeCotangent.Aux.cotangentEquivProd_symm_apply`.
It exhausted the existing 1,800-second declaration limit. The sealed 45M
checkpoint is intact in `../mathlib-alignment-5m-20260913-with-terminal`.
This investigation uses the original serial OCaml 4 pipeline, not PR #78.

## Investigation history

`prepare.py` extracts the target and **all dependency proofs** with the existing
proof-preserving slicer, recording input/output hashes in `slice.json`. It emits
prefix/target/whole NDJSON consumers. Extraction is guarded separately (7 GiB
hard limit, no swap, 3 GiB reserve); theorem replays use the unchanged production
16 GiB limit and 1,800-second per-declaration timeout.

The production samples repeatedly visit `compare_under`, `fast_test_under`, and
the syntactic equality memo. A concrete false-miss issue was isolated:
`SyntaxPairs.equal` compares physical identities of `usubs` wrapper pairs, even
though FCLOS inspection reconstructs these wrappers around unchanged components.
The candidate uses the existing `eq_usubs_fast` predicate for those components,
retaining physical raw-term keys, universe distinctions, captured substitutions,
and per-probe cache lifetime. No checking rule or work allowance changes.

Lean comparison: `src/kernel/expr_eq_fn.cpp` at
`98dc76e3c0a9b856c9b98726b713fb04fab16740` compares expression identity and
cached structural hashes, then memoizes shared expression pairs during one
equality traversal. The Rocq adaptation cannot blindly use expression pointers:
raw templates are interpreted under suspended substitutions and universes.
Those contexts must stay in the key, but incidental tuple allocation must not.
The new equality remains compatible with the existing hash (which omits the
context), so it changes cache hits without invalidating hash-table lookup.

This does not port Lean's non-moving object-address hash into OCaml, share a
memo across reductions, change congruence order, or increase a checking budget.

Evidence so far:

- `syntax-baseline-2.log`: the old source misses a completed equality after
  allocating fresh wrappers around identical substitution components.
- `syntax-candidate-1.log`: the candidate hits; different captures and universe
  instances remain negative.
- `syntax-candidate-2.log`: also exercises fresh FCLOS cells through the actual
  `fast_test_under` entry point, retaining the same read-only memo.
- `private-candidate-1.log`: the existing private witness/conversion suite passes.

Extraction retained 2,133,796 records and abstracted zero dependency proofs.
The initial `baseline-prefix` stopped on a sparse-ID parser error, not a proof
failure. Like earlier diagnostic slices, `convert.py` uses the existing arena
stream converter to preserve those sparse identifiers; `replay.json` binds the
conversion, original extraction and output. `baseline-stream-prefix` checks the
dependency proofs with the unchanged production worker and importer.
`CotangentDiagnostic.v` has a separate 120-second diagnostic cutoff; production
and `CotangentStreamTarget.v` retain the 1,800-second declaration limit.

The baseline dependency prefix passed in 1,065.48 seconds, with every proof
retained (`baseline-stream-prefix/result.json`). Its exact target then hit the
separate 120-second cutoff (`baseline-target-diagnostic/result.json`). The slow
fallback is conversion call 365 in that replay. This corroborates the original
production timeout; it is not a successful theorem check.

**Candidate 1 did not solve the timeout and was not promoted.** Its focused diagnostic
is `candidate-target-diagnostic-1`. Worker SHA256:
`9685f52c1152ff6f7a054a7d654f58b7176b0e593c7477eda608b5f8047b359a`.
Checker SHA256:
`9ca10180e12d7905000c87abba66cf594cecf67fff5f143a375b94e38a6c15a6`.
`../kernel-alignment-pass/importer.0UZwR90I` is an ABI-only rebuild of
`importer.q64CBLVp`, preserving its constructor-context fix and all other source.

Old worker/checker binaries and `conversion-baseline.ml` are preserved here.
The old worker SHA256 is
`a363c589e05023fecfe27114ef587aeeb88715717929eafedbd3dece21c00b36`.
The cache correction alone still hit the 120-second diagnostic cutoff. It is
not the explanation for the subsequent performance improvement.

## Candidate 2: reduce applied projections through aliases

The stalled conversion compared every parameter of
`DFinsupp.instEquivLikeLinearEquiv` under an applied projection. Its body is
`inferInstance ... (LinearEquiv.instEquivLike ...)`, not a direct record
constructor, so the previous constructor-wrapper recognizer missed it. The
result was a large detour through algebraic instance parameters before exposing
the selected function field.

Lean 4.29's `type_checker::is_def_eq_core` runs non-cheap projection WHNF before
application congruence. Bare projections have a separate lazy source-comparison
path. Reference: `src/kernel/type_checker.cpp` at
`98dc76e3c0a9b856c9b98726b713fb04fab16740`, particularly `reduce_proj`,
`lazy_delta_proj_reduction` and `is_def_eq_core`.

The Rocq adaptation recognizes a transparent, defined constant with record
arguments, followed by projection(s), followed by an application. It gives
ordinary delta/projection reduction priority over source-argument congruence,
including through aliases. It does **not** establish equality itself, erase
proof obligations, unfold opaque bodies or alter bare-projection handling.
Constant records with no source parameters retain method-argument congruence.
The existing dependency-heuristic flag gates the change. No time, memory, cache
size or congruence allowance was increased.

Focused validation (the user explicitly waived the full suite):

- `candidate-target-diagnostic-2`: target passed; 2.90 CPU seconds for its declaration.
- `candidate-target-2`: same proof passed without conversion diagnostics at the
  normal 1,800-second declaration limit. Declaration: **2.934 CPU seconds**;
  whole process, including loading the prefix and writing the artifact:
  50.43 seconds; guarded peak 843,448 KiB. This is a proof-preserving slice replay,
  not a claim of original-order 45M–50M completion.
- `applied-projection-tests-2`: alias forwarding in both directions, distinct
  captured fields and method arguments, real opaque definitions, and constant
  method congruence all behaved as expected. The test finished in 5.15 seconds.
- `candidate-target-2/independent.json`: independent target-artifact recheck;
  dependencies reuse the separately proof-checked prefix, foundation and stdlib.
- Permanent cases added to `test-suite/success/projected_constant_congruence.v`;
  no full regression suite was run for this candidate.

Candidate 2 worker SHA256:
`bb48befc1cd8dd8c14df1ae1db1822a8a5fab1ccb40c95e53a38e7f3082d65e3`.
Checker SHA256:
`b8a115e119c3c99f2ef7a2ceb11a2c2e01acf0c3fba01f632c2ff20f9da81541`.
`../kernel-alignment-pass/importer.vnOgrcwY` rebuilds the exact existing
`importer.q64CBLVp` sources against this kernel ABI.

`resume.py` requires the successful focused results and independent check,
verifies the sealed 0–45M checkpoint chain, and resumes the original serial
pipeline at **45,000,001**, using a new hash-pinned consumer certificate without
rewriting producer seals. It retains 5M checkpoints, 1,800 seconds/declaration,
16 GiB workload memory plus 3 GiB reserve and no swap. It launches
`rocq-mathlib-alignment-5m-cotangent-v2.service`, without automatic restart or
assistant monitoring after the startup check. `resume-approval.json` records
the launch; absence of that file means the restart has not yet been approved.
Full Mathlib verification remains unfinished.

## User-approved memory increase after the 50M save failure

The resumed import finished processing the 45M–50M chunk, but the 15 GiB RSS
guard stopped checkpoint packing before the 50M artifact was committed.
The last valid checkpoint remains 45M. This was not a declaration failure.

The user authorized a **25 GB** memory cap and a **2 GiB** system-memory reserve.
`resume-25gb.py` applies that resource-only override to the existing compiler
command, preserving the sealed plan and all proof settings. Both RSS and cgroup
hard/high limits are 24,414,062 KiB (25 decimal GB rounded down); swap remains
disabled. `test-memory-25gb.py` checks that no other environment fields or compiler
arguments change. This raises the allowance; it does not optimize serialization.

`memory-25gb-approval.json` binds the runtime policy to the existing validated
worker/importer and is included in subsequent checkpoint inputs. The detached
service is `rocq-mathlib-cotangent-25gb.service`, continuing from 45,000,001 with
the same 5M checkpoint interval. The generation's `progress.json` and `latest`
log link remain the status locations. No full test suite or ongoing assistant
monitoring is requested for this restart.
