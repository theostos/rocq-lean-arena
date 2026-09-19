# Remote continuation brief — 19 September 2026

This is the current specification for continuing on `ssh homepc`, in
`/home/theo/Documents/github/rocq-lean-typechecker`. Read this and `HANDOFF.md`
before acting. Older reports/receipts are historical evidence, not current
instructions to resume a laptop-specific release script.

## Mission and engineering constraints

Finish a **complete Rocq import/typecheck of the pinned Mathlib export**, retaining
all proof bodies. The export has 100,001,405 NDJSON records; records are not
theorems, and progress through records is not a workload-weighted percentage.

The intended method is to understand the relevant **Lean kernel implementation**,
identify why the translated workload behaves differently in Rocq, and adapt the
useful strategy robustly. This includes representation and sharing, substitution,
inference/WHNF/equality caches, unfolding order, projections, recursors and literal
computation when implicated by evidence. It is not a request for ad hoc theorem
exceptions, limit tuning, an unchecked fast path, or wholesale copying of Lean
code. Preserve Rocq's binder, universe, transparency, relevance, mutable-closure
and moving-GC invariants. Hashes may select candidates, never certify equality.

Do not assume the kernels are already fully aligned. A complete corpus run is
an acceptance milestone, not a proof of soundness, minimality or judgment
equivalence. Keep the existing compatibility assumptions explicit: Lean Prop is
translated to SProp, the foundation enables definitional UIP, and imported
elimination flags are not the same as strict native Rocq checking. See the
[review map](mathlib-handoff-review.md) for known boundaries and prior repairs.

## Exact state at transfer

| Item | State |
| --- | --- |
| Arena sources | `handoff/mathlib-20260919`, child of Penrose arena snapshot `9ee84cb0c4433b2430a93f210f0d1d85197fbc87`; documentation and completed failure evidence only. Its exact commit is in `/home/theo/mathlib-handoff-20260919/arena-source.json`. |
| Custom Rocq sources | `_worktrees/rocq/compact-peano-view`, `7b45cab763216a35b043afd356d1852f18e09b8d`. Includes the earlier full custom snapshot `d17b66af824e344393b126e57fbcec99174f926a` plus the six-file Penrose repair. **These sources are already on homepc.** |
| Serial importer sources | `_worktrees/rocq-lean-import/cslib-ndjson`, `5cf335ec68a41ad23dd720018a191f95b161a5cc`. Includes the production constructor-context repair. This is not PR #78 or the delayed-opaques experiment. |
| Other source pins | `docs/handoff-20260918.json`; `python3 scripts/handoff/install_sources.py --check` passed on the remote during this update. |
| Remote runtime | Custom worker/checker and importer plugin have **not** been built or validated. Expected binary outputs and the Mathlib NDJSON export were absent. An installed system Rocq is not a substitute. |
| Transferred data | Sources, harnesses and small historical receipts/logs. No executable, opam switch, multi-GB export or resumable checkpoint chain. The user chose regeneration. |
| Saved local prefix | 55,000,000 records compiled, saved and freshly reloaded in a generation that used qualified worker migrations. Not a line-1 pass on one final kernel. |
| Latest local attempt | `work/mathlib-alignment-5m-20260913-with-terminal/attempts/20260918T135919175502Z`, exited 1 at 2026-09-18 16:04:44 UTC. No 60M checkpoint was saved. |
| Next unresolved declaration | **58,521,298: `ProofWidgets.Penrose.Diagram`**, timed out at the unchanged 1800-second declaration limit. |

Nested source repositories are not submodules. A root `git pull` does not update
them. The Penrose and current documentation follow-ups were delivered through
SSH bundles, **not published to GitHub**. Preserve the bundles and receipts; do
not reset/switch unrelated work to make a pin mismatch disappear.

## What passed, and what did not

The preceding proof at **58,521,284** is
`_private.ProofWidgets.Component.PenroseDiagram.0.ProofWidgets.Penrose.Diagram._proof_1`.
It mentions an embedded string of 2,786,515 characters. The importer expands
strings to reflected characters in a list; there is no new compact-string
representation in the qualified repair.

The qualified repair addressed pathological physical-memo collisions, recursive
traversals, application inference/cache fingerprints, large already-checked
type comparison, and standalone serialized-value validation. See the detailed
[Penrose report](../work/mathlib-penrose-repro/README.md). The laptop's final
exact proof replay passed in **660.31 wall seconds**, including load/save, with
about 3.71 GiB peak scope memory. Its fresh independent **target-only** check
passed in **587.80 wall seconds**, about 2.65 GiB peak. Ten native test groups,
18 focused fixtures and the previous Padic proof replay also passed. These are
not remote timings or a recursive independent check of all Mathlib.

The resumed full chunk then passed that proof and reached the later **definition**
`ProofWidgets.Penrose.Diagram`. It timed out. The final diagnostic samples show
`Conversion.application_key`, `try_congruence`, `eqwhnf`, `drive`, `ccnv` and
argument-stack comparison. This establishes where samples landed, **not the
root cause** or an infinite loop. The terminal guard log reports a peak of
22,083,312 KiB below the 24,414,062 KiB hard cap; the recorded failure was the
declaration timeout, not an OOM termination. More RAM alone is not a demonstrated
fix. Whether string-hash computation, repeated comparison, unfolding or another
operation dominates still needs a targeted measurement.

The exact failing export record is:

```json
{"def":{"all":[2119212],"hints":{"regular":2},"levelParams":[],"name":2119212,"safety":"safe","type":56051509,"value":56051520}}
```

Raw logs and frozen progress/result/input records are in
`work/mathlib-penrose-diagram-failure-20260919/`. Its `manifest.json` records each
source path, byte count and SHA-256. These are copies of a **completed laptop
failure**, not newly executed tests. `attempt/status.json` is the runner's last
intermediate state; `result.json`, `progress.json` and the terminal logs establish
the outcome. Do not edit the old Penrose README or validation receipt to describe
the newer failure: they bind the earlier successful qualification.

## First remote session: preflight and rebuild

1. Read this brief, inspect `git status` in the root and nested checkouts, and run
   `python3 scripts/handoff/install_sources.py --check`. Verify the failure
   evidence hashes using the manifest. No build or run is launched by that source
   check. Record any intentional changes separately from the starting pins.
2. Recheck `df -h .`, `free -h`, existing workloads and the active toolchain.
   On 19 September this host had 188 GiB total RAM, about 132 GiB available, but
   **only 62 GiB disk free**. Budget for the reference Lean/Mathlib build, 5.64 GB
   NDJSON, Rocq builds, and cumulative checkpoint artifacts. Do not assume 62 GiB
   suffices or remove user experiments. `opam`/`ocamlc` were on the SSH PATH;
   `dune`/`rocq` were not. Inspect switches instead of assuming dependencies exist.
3. Create/use an isolated build environment without changing the user's default
   switch. Producer versions: OCaml 4.14.2, Dune 3.23.1, ocamlfind 1.9.8, Zarith
   1.14. Install Yojson and requirements from the pinned Rocq `INSTALL.md` and
   opam files. Use one OCaml toolchain for runtime and plugins. Do not silently
   migrate to OCaml 5 or the parallel importer during this investigation.
4. Build the **pinned custom kernel**, its runtime/core/plugins and standalone
   checker, following that checkout's build instructions. Expected development
   prefix: `_worktrees/rocq/compact-peano-view/_build/install/default`; worker
   and checker outputs are `_build/default/topbin/rocqworker.exe` and
   `_build/default/checker/rocqchk.exe`. Rebuilding just a binary against a stock
   installed core library is not sufficient. The laptop's Ubuntu 24.04 binaries
   require newer glibc than remote Ubuntu 22.04, so do not copy them.
5. Build pinned stdlib `3e47b26f345f36e375d81ade399eed0e310984b3` against that
   kernel, retaining its in-tree `theories/*.vo` layout expected by the runner.
   Build the pinned importer with that prefix's `rocq makefile` and matching
   `COQBIN`/`OCAMLPATH`. Its Makefile accepts `COQBIN` and `CAMLPKGS` (Yojson).
   Provide the runner's expected `_build/findlib/yojson/{META,yojson.cmxs}` in
   the selected importer tree. Verify loaded libraries resolve to this build.
6. Qualify the new runtime with focused kernel/importer tests and a small actual
   import/save/fresh-reload test. Record commands, versions, source diffs, binary
   and plugin hashes, time and memory. Old laptop hashes are provenance, not
   the expected digest of a new native build or a validation waiver.

Build scripts under `work/` are historical harnesses, not a tested remote setup
installer. In particular `work/kernel-alignment-pass/build-importer.sh` assumes
laptop opam paths, including `coq820_dev/lib/yojson`; Penrose `build.sh` assumes
`rocq93_native/bin`. Adapt paths for the actual isolated switch. Do not blindly
run those scripts or rewrite their prior output/validation records.

## Pinned Lean comparison and reproducing the new failure

Reference Lean is **4.29.0**, commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740`; Mathlib is
`8a178386ffc0f5fef0b77738bb5449d50efeea95`. Use that Lean source for kernel
comparisons. Do not use the older 4.27 source or an unrelated `_deps/lean4-src`
HEAD simply because its directory is present. Fetch the exact reference source
into a separate checkout if needed and record its revision.

Regenerate the export using reference arena `4ce4d513...` and exporter
`3de59f10...`, already pinned by the installer with the explicit
`leanprover/lean4:v4.29.0` toolchain. Build the exporter in its directory with
`lake build`, then from `_deps/lean-kernel-arena` use
`uv run lka.py build-test mathlib`. The runner expects
`_build/tests/mathlib.ndjson` and `mathlib.stats.json` there. Check header,
revision metadata, 100,001,405 records, 5,636,308,621 bytes, and SHA-256
`a466d22a521f0fc0406b6d0ece2173f2b2e3d9eb4d8bc26a5e14316d39944d27`.
A difference requires investigation/new export identity, not forcing a match
or assuming historical record numbers still denote the same declarations.

Next, isolate **the definition at 58,521,298**, not just the already repaired
proof. The existing `work/mathlib-penrose-repro/prepare.py` selects only the
earlier theorem. Adapt the slicer harness into a **new directory and new
receipts** for the definition, retaining all dependency proofs and confirming
`abstracted == 0`. The old script's outputs/receipts already exist in the source
snapshot; it deliberately refuses to overwrite them. `convert.py` is also
theorem-specific (`thm` lookup); selecting the new `def` requires adapting that
lookup and recomputing the target interval. Do not reuse the earlier 9,940-record
slice or its target position as if it included the definition.

Sparse diagnostic slices cannot simply be fed to the consecutive-ID native
NDJSON reader. Preserve proof terms and use the exact pinned converter installed
from `scripts/handoff/arena_converter.py`, or implement/validate consistent ID
remapping. Keep source/export/converter hashes and the target mapping. No axiom
replacement, missing-dependency skip or proof erasure in acceptance replays.

Measure baseline phases separately: parsing/translation, inference/conversion,
save, reload and standalone checking. Inspect the actual repeatedly compared
terms and reduction path. Compare Lean's expression/literal representation,
conversion/WHNF cache keys and scope, reduction order, and relevant literal
operations **when implicated**. There is no measured apples-to-apples Lean versus
Rocq runtime ratio for this definition in the handoff. Separate representation
expansion costs from avoidable repeated work before choosing a repair.

For a candidate, document the invariant and fallback path. Test the exact new
definition and the original Penrose proof, plus focused controls for any touched
cache, binder/universe/relevance, sharing, GC, projection or traversal behavior.
Reuse the earlier native/focused harness sources, but emit fresh outputs; retain
negative controls, not just Mathlib acceptance. Include the prior Padic case
when touching its shared conversion paths. Run a fresh independent target check
and report its dependency scope honestly. A full suite is not required for this
documentation transfer; do not claim regression freedom without testing a repair.

## Launching the full remote experiment after qualification

The user wants to continue the **serial direct-NDJSON loop**, with checkpoints
every **5,000,000** records. After qualifying the repair, use a **new generation
directory starting at line 1** on homepc: no resumable local 55M files were
transferred. Once a valid remote chain exists, resume it from its own latest
sealed checkpoint. Worker/source changes need explicit migration qualification;
never edit old producer seals to bypass identity mismatches.

Runner: `scripts/mathlib_ndjson_loop.py`, backed by `run_chunked_import.py`.
Do not use the older Lean-4.27 `scripts/prepare_mathlib.py`. Explicitly set
`--interval 5000000 --line-timeout 1800 --importer <new-built-importer>`;
defaults are **1M/600s**, not the intended policy. The runner's old `TARGET`
and `trace_line` at 4,855,906 are diagnostic metadata, not the start position or
the current Penrose target. `--smoke` expects a generated NatBeq export that was
not included as a binary/data handoff; regenerate that fixture or use an actual
available small proof-preserving test.

**There is not yet a tested remote 25-GB production launcher.** The generic
chunk runner rejects budgets above 16,384 MiB in both preparation and validation.
The laptop's 25,000,000,000-byte limit used a separate, artifact-bound override.
Do not pass `--memory-mib 25000` and assume equivalence or assume that changing
an environment variable bypasses the plan's checked limit. Implement/review a
portable explicit resource profile for a new remote generation before launch,
recording the budget, reserve and unchanged proof policy. The laptop used a
2-GiB host reserve; generic runners use 3 GiB and a 15/16 RSS margin. Reconcile
those deliberately with coexisting workloads. No silent use of all 188 GiB,
removal of guards, or timeout increase disguised as the algorithmic repair.

Keep Fail mode; unset missing-quotient skips, parsing-only and lazy instantiation;
retain the qualified import-alignment configuration and 1800-second declaration
timeout. Keep workload swap disabled, atomic checkpoint saves, input hashes and
fresh-process reload verification. Preserve the raw diagnostics. Do not run
old `work/*/resume.py release` scripts: they reference laptop artifacts/seals.

Launch detached only after these prerequisites, record the service/job name and
new generation path, and show the user where to inspect progress. No ongoing
agent monitoring is requested. Built-in logging and stall sampling are useful
and need no conversational polling. With the chosen generation path:

```sh
python3 scripts/mathlib_ndjson_loop.py status --directory /absolute/new-generation
tail -n 40 /absolute/new-generation/latest/MathlibTo5000000.run.log
```

The module filename changes with the current chunk; `progress.json` provides
the actual `run_log` path. A declaration's `line` is the current activity, not a
completed checkpoint; `checkpoint_through` is the saved prefix. Distinguish
checking, serialization, fresh reload, resource refusal, timeout and completion.

## Completion and final review

Acceptance requires reaching the expected export EOF with no failed/skipped
declarations, saving the final partial checkpoint through 100,001,405, successful
fresh reload, and preserved source/runtime/export identities and logs. Report
independent checking separately: `rocqchk -norec` on a target is not a strict
recursive recheck of its dependency closure. If there are further failures,
continue evidence-driven, qualified fixes; do not mark a partial run complete.

For the final deep review, use `docs/mathlib-handoff-review.md`, the preserved
base-to-snapshot source diffs, new commits/diffs, and per-worker receipts. Record
which changes were retained or superseded, the Lean reference/invariant for each,
and exactly which worker checked each part. Deleted checkpoints and missing
conversation history cannot be reconstructed from Git; do not fill those gaps
with invented evidence. This transfer itself adds **no kernel change**, runs
**no remote validation**, and starts **no remote Mathlib job**.
