# MvPolynomial basic-open conversion slowdown

Target: line 18,947,260, `MvPolynomial.mem_image_comap_C_basicOpen`.

## Current status

Space cleanup after the canonical 19M replay/reload succeeded: the loop paused
at its 5 GiB disk admission guard, then the user requested maximum removal of
unused checkpoints. The obsolete replay binaries (including this investigation's
prefix, isolated target, and earlier `.vo.gz` archives) were deleted; their
sources/logs remain. The complete approved validation batch below, the canonical
1M-through-19M dependency chain and latest reload are intact. The resume gate
passed again, and the service was restarted from 19M. See
[`../checkpoint-cleanup-20260911/README.md`](../checkpoint-cleanup-20260911/README.md)
for the exact deletion inventory and recovery limitations.

**Validated; canonical loop resumed from the sealed 18M checkpoint.** The bounded-first worker
`0343f4a860d43380cd111a3e700ed9bf5b464da10a1d08be353eb2b21e5a1db7`
passes both targets. Its Mathlib theorem/save completed in 560.07 seconds,
including 200.087 CPU seconds for the declaration; `.vo` SHA256
`ed27ecb5868f412faa22e58f790e96db724031451265cb0fb5f76a0ddd827cf6`.
The approved batch is **`validation-8gccux_c/`**: all eight focused kernel fixtures
passed. The full original-order replay also passed the reported theorem
(declaration CPU 494.753 to 690.233, 195.480 seconds) and completed its save:
exit 0, 1,097.52 seconds total, peak guarded memory 9,125,192 KiB, `.vo` SHA256
`4d93b20859cd2d2b189783c7a7c59f4951738999acc0e758731ccd2334b2527e`.
The fresh reload/save passed in 360.02 seconds (artifact SHA256
`1e17a8745630a8032630ad8cd7a01301c79afecce9cef9c9b8075044b3461de3`).
All **28 kernel fixtures**, the closure-lifting unit test and **44 importer
fixtures** passed, including the unchanged UTF-8 and adder regressions. The
runner suite ran **201 tests: OK, two skipped**. All 18 existing checkpoint
seals and the export/toolchain hashes were verified read-only.

`resume.sh --check` passed. The script is pinned to this batch, worker, source
hashes, saved artifacts and regression results. The canonical loop was started
as **`rocq-mathlib-ndjson-closure-syntax.service`**, with its supervisor log at
`../mathlib-ndjson/closure-syntax-resume.supervisor.log`. It uses the existing
1,800-second declaration timeout and 16 GiB/no-swap worker guard. No isolated
artifact was promoted into the canonical checkpoint chain. No commits/pushes.

The final repair retains the copy-free, 1,024-node structural shortcut and
gives the original dependency/constructor-guided strategy 256 weak-head
comparisons before trying the relevance-aware strategy with fresh closures.
The failed constructor-filtering experiments are not in the selected source.

Superseded diagnostic workers were losslessly archived as `.gz` by
`archive-superseded.sh`, with a byte-for-byte comparison before removing each
uncompressed copy. Restore a retained worker archive with
`gzip -dk path/to/worker.exe.gz`. The earlier isolated `.vo.gz` archives and
prefix were subsequently deleted by the user-requested checkpoint cleanup above.
The baseline and selected workers, current validation artifacts and all main
canonical checkpoints are retained.

## First validation failure and strategy controls

The first final-validation batch failed the unchanged
30-second UTF-8/bitvector regression at export line 146,567. The reported
MvPolynomial theorem, full 18M-to-19M replay/save, fresh reload, 27 kernel
fixtures and closure-lifting unit test all passed, but the importer suite did
not complete. `validation-0xdvrudn/` therefore has no `passed.json`, and
the resume gate refused to run. The clean-first candidate is preserved as
`conversion.clean-first.ml` / `rocqworker.clean-first.exe`.

The first experimental adjustment retained constructor-argument unfolding
preferences in the dependency-first pass even with constructor relevance
enabled. Saved as `conversion.keep-constructor.ml` /
`rocqworker.keep-constructor.exe`, worker SHA256
`851e26e1dd3f8ee8188e0ecb25255acce92b2dbb9e0bf46b94819cd27da5cddf`.
It restores the UTF-8 target (5.04 seconds), but its Mathlib target trial was
deliberately stopped after 212.38 seconds (exit 143) as record-guided unfolding
grew RSS past 10,010,224 KiB while still in conversion 770. This was not a timeout.

A subsequent candidate narrowed that preference to **data constructors**, ignoring
eta-record constructor arguments when the typed relevance-aware pass compares
different references. Its worker is `rocqworker.data-constructor.exe`, SHA256
`ade3fdd4f716a0e9cdc657cd29d6de8b312fbc2999c6e50a75f1ddbb588fcf82`;
source snapshot `conversion.data-constructor.ml`. UTF-8 passes in 5.12 seconds
(`utf8-data-constructor/`), matching the current baseline's 5.04 seconds
(`utf8-baseline-target/`). Its Mathlib trial was also stopped deliberately
while allocating roughly 9.9 GB; the queued final validation refused to start.
Neither constructor-filtering candidate is selected.

The current candidate uses a **bounded original-strategy attempt**, then the
previously successful relevance-aware attempt. The original attempt may perform
256 weak-head comparison steps; a distinct exception escapes inner congruence
probes and triggers a fresh attempt with fresh closures and local caches. This
does not certify an equality or cap the fallback conversion. The original
constructor preferences are restored unchanged. Saved as
`conversion.bounded-first.ml` / `rocqworker.bounded-first.exe`, SHA256
`0343f4a860d43380cd111a3e700ed9bf5b464da10a1d08be353eb2b21e5a1db7`.
UTF-8 passes in 5.04 seconds (`utf8-bounded-first/`). `StrategyBudget.v` also
passes: 400-argument comparisons exercise both successful fallback and rejection
of changed arguments, with the entry trace confirming retries on positive cases.
`bounded-first-target/` checked the Mathlib theorem successfully (declaration
CPU 83.542 to 283.629, 200.087 seconds) and saved its artifact. The queued
wrapper then ran final validation after checking the worker and artifact hashes.
That batch passed, including 28 kernel fixtures, and this candidate is now the
approved worker used by the resumed loop (see Current status above).

`utf8.py` rebuilds/replays a small UTF-8 prefix with the
matching legacy importer/foundation and existing standard library. Earlier
setup failures (old standard-library assumptions, then wrong plugin path) are
preserved; they are not proof-checking failures.

The isolated theorem replay **passed and saved its `.vo`**, with all type
queries enabled and the normal 1,800-second declaration limit:

- `no-copy-normal/`: exit 0, 567.51 seconds including loading/saving;
  declaration checking took 195.81 CPU seconds (82.050 to 277.863).
- Saved worker: `rocqworker.no-copy-stats.exe`, SHA256
  `0440ba0701ea7c4f62accc8d1ae58136d71288079d15fba1930f272aee682199`.
- Saved artifact SHA256:
  `2810949eb4ab09baacbe8abe73609a0ff5d3ba15f48795b1399dc8ad0722a522`.
- Guard peak: 9,410,392 KiB, below the 16 GiB/no-swap limit.

The first successful isolated candidate performed a bounded structural comparison through regular
suspended substitutions, carrying relocation information rather than allocating
lifted constructor trees. Unsupported cases (including higher-order substitution
entries) and budget exhaustion fall back to ordinary conversion. The existing
typed constructor-relevance strategy was enabled in the first dependency-ordered
pass; the final strategy-order correction is described above. There are no new axioms, unchecked imports, type-query bypasses, larger
conversion caches, or changes to canonical timeout policy.

Temporary scalar counters have been removed. The clean worker SHA256 is
`1e1546158de5c89a4ffcec406fc3cd0d71fedb6c7c2105c3919407a6247535c1`.
The CClosure interface CRC remains `563d1b3f4be65c3c17f24a31891a8000`,
matching the pinned importer plugin; that plugin was not rebuilt.

`validation-0xdvrudn/` was the first validation batch. Its seven focused kernel
fixtures have passed. The clean full original-order replay also checked the
reported theorem successfully (kernel declaration CPU 484.371 to 675.757,
191.386 seconds). The full replay and save completed with exit 0 in 1,079.63
seconds, peak guarded memory 9,124,392 KiB. Its `.vo` SHA256 is
`cad8b0529183c181e7d51951de43f70777d3d52f99f858d1b8dbc2ee4d86a737`.
The fresh reload/save also passed (354.36 seconds; artifact SHA256
`7c68dd8487edfed406b70142cc41f5ecd56becf9c5c59a1f779e6bbb63a20bc5`).
All 27 kernel fixtures and the closure-lifting unit test have passed. The 44
importer fixture suite failed on UTF-8 as noted above; the remaining fixtures
and runner tests did not run in that first batch. No resume occurred with that
candidate. The remaining sections record the chronological investigation.

## Baseline and setup

The canonical attempt `20260911T153849286293Z` reached the theorem with the
validated Matrix.mul_fin_two repair and repeatedly sampled deep conversion
work. The three SIGUSR1 events are diagnostic samples, not a timeout or an
assertion. The sampled leaf functions alone do not establish the cause.

The main service was stopped for isolated investigation before its normal
1,800-second declaration limit. Its checked 18M checkpoint remains intact.
`canonical-status-before-stop.json` preserves the last live status. The runner's
main progress JSON may still show the stopped worker; consult the service or
the isolated replay logs for current activity.

Baseline worker SHA256:
`fdb0d78a70bedd2215f0216bad820f5d745c78129622f8be8c4fabe7e6bc4ad5`.
Baseline conversion source SHA256:
`d97b886108dbcb2ebe263274a1b88d5ebf857b437ffa79c501cb5c624c4aa7a6`.
They are preserved as `rocqworker.baseline.exe` and `conversion.baseline.ml`.

`prefix-source/MathlibTo19000000.v` checks 18,000,001–18,947,259 in original
order/module context from the sealed 18M checkpoint. `Target.v` checks the next
theorem with normal settings. `Trace.v` uses a 120-second diagnostic limit;
`PlainTrace.v` additionally disables the dependency heuristic as a control.
Neither changes canonical sources, limits or proof checking.

All replay processes take the global launcher lock and use the 16 GiB/no-swap
guard. Checkpoint seals and the NDJSON export are verified read-only first.
Additional path-tracing instrumentation is experimental and was removed before
the final validation batch. Saved experimental workers are diagnostic artifacts,
not approved full-run binaries.

## Initial results

- `prefix/`: exit 0, 797.98 seconds including load/save; saved `.vo` SHA256
  `796ad89995b236920aceed9be3b524a8023121e08ad696b1cdaeef5bba632971`.
- `baseline-entries/`: hits the isolated 120-second declaration limit in
  conversion call 770, after an earlier expensive equality comparison in call
  686 eventually finishes. Declaration CPU starts
  at 84.605; body translation is finished at 84.704; kernel checking starts
  at 84.724. Call 686 starts at 110.829. Full process exit 1 after 206.20 seconds.
- `plain-oracle/`: also hits the 120-second declaration limit, still in call
  686, with only the dependency heuristic disabled. Exit 1 after 203.98 seconds.
- `path-686/`: traces more than eight million nested comparison steps in call
  686, through `Quot.lift`, `Multiset.map`, polynomial semiring methods,
  tensor-product lifts and residue-field algebra structures. Call 686 finishes,
  but the declaration hits the diagnostic limit later. Exit 1, 200.01 seconds.
  Diagnostic worker SHA256:
  `ba5640e2800a45087597c18ef358e9553b45e72e490c1006fb8c2cc3bbf9628c`.

An earlier queued trace for call 411 was canceled before starting when the
entry trace advanced to the much larger comparison in call 686. No artifact
was removed. Neither a sampled call nor the last call observed while running
should be confused with the final call at timeout.

Further one-factor experiments:
- `no-unit-queries/`: diagnostic disabling of flexible/local unit-type queries,
  not a production repair. Worker
  `8c8a5233b29c08d5955a55e9b6ce16b977273534d26d0143a81efbc792c3d2cc`.
- `fast-syntax/`: bounded structural comparison through suspended substitutions,
  with unit queries enabled normally. Worker
  `43dedf0292adc920fb63e0441fe9e1e0b006038c101acac0d6af98963218ff39`.
Both have source/worker snapshots. Remove diagnostic code before production
validation; no repair has yet passed the full theorem.

Completed controls:
- `no-unit-queries/` still times out in call 770 (201.49 seconds total).
- `fast-syntax/` reduces call 686 from 45.81 seconds to 0.34 seconds, but
  still reaches the diagnostic limit in call 770 (200.69 seconds total).
- `large-memo/`, with the baseline worker and capacity 1,048,576, makes
  call 411 slower (about 51 seconds versus 24 seconds). It times out in 686
  after 200.63 seconds total. Increasing capacity is not a repair.
- `fast-path-770/` times out in 770 after 200.23 seconds total. The original
  path printer only printed when a power-of-two event was `eqwhnf`; it missed
  important `eqappr` events. Later diagnostic snapshots print either phase.

The `fast-no-unit-gdb/` control disables flexible/local unit-type queries on
top of fast syntax. A SIGUSR1 sample at 19:09:53 shows an independent expensive
path: `transparent_inductive_after_applying` -> `fresh_args` -> `to_constr` ->
`lift_substituend`. This eagerly expands shared argument closures merely to
classify a record type. It motivates the separate `no-transparent-type` control;
it does not by itself establish that disabling the query solves the theorem.

Additional trials are pinned to separate saved workers and serialized by the
launcher lock: selective admission to the successful-conversion cache, a
4,096-step speculative congruence work budget, and the type-query control.
The first normal-limit fast-syntax replay was canceled while still waiting
for the lock (no worker or output artifact), to prioritize the diagnostic
controls. A normal-limit replay is still required before accepting any repair.

- `fast-no-unit-gdb/`: diagnostic timeout in 770, 202.44 seconds total;
  therefore disabling unit-type queries is not sufficient even with fast syntax.
- `selective-memo/`: diagnostic timeout in 770, 204.22 seconds total. Caching
  only comparisons that perform at least 16 uncached nested comparisons reduces
  cache traffic but does not resolve the theorem.

`conversion.bounded-copy.ml` / `rocqworker.bounded-copy.exe` add a read-only,
4,096-node expanded-syntax preflight before copying arguments for the optional
transparent record-type query, on top of the fast-syntax trial. Unsupported or
too-large closures decline that query, not conversion itself. This candidate
is queued for a normal-limit replay; it has NOT passed validation.

The **relevance-first control** is baseline plus changing the dependency-first conversion pass from
`convert false ... true` to `convert true ... true`. Its separate saved worker
is `rocqworker.relevance-first.exe` (SHA256
`9351b76babdc7688e6a3eabca15cbf5d5dda95ffd375c02ab4f753a5848733b1`).
This uses an already-existing strategy, but changing its order has not been
validated. Do not use the old pinned full-run resume helper with this build.

- `fast-work-budget/`: times out in call 411, before reaching 686 or 770;
  204.53 seconds total. This is worse than the ordinary depth-only limit here.
- `no-transparent-type/`: times out in 770, 205.23 seconds total. Disabling
  that query alone does not resolve the theorem.
- `relevance-first/`: call 411 takes under five seconds and 686 about 31
  seconds, but the declaration still times out in 770.

Queued normal-limit trials were canceled *before acquiring the lock*, with
no worker/artifact, as short controls exposed additional costs. The bounded-copy
normal trial has not run. `no-type-queries/` tests both diagnostic query-disabling
flags together with a short limit. The actual normal-limit candidate is now
`fast-relevance-normal/`, retaining all type checks and combining the two
independently measured partial improvements.

An earlier kernel source/build was **experimental fast syntax plus relevance
first**, saved as `conversion.fast-relevance.ml` and
`rocqworker.fast-relevance.exe`, SHA256
`dc58a6bc3bd51d3ebbf530dea68840ba1b08659a5acfa3e440514aabe829a895`.
It contains neither the new path/query controls, the cache-admission experiment,
the work budget nor bounded-copy changes. `ClosureSyntax.v` adds positive and
negative kernel checks for substitutions, binders, data, opacity and universes;
its results are recorded below. This was not the final selected repair.

## Final experiments and focused checks

- `no-type-queries/`: disabling both optional query families still hits the
  diagnostic limit in conversion 770 (205.38 seconds total).
- `fast-relevance-normal/`: the initial fast path used `mk_clos` on substituted
  variables. That eagerly copied lifted constructor trees before the comparison
  budget applied. The trial was deliberately stopped after 430.73 seconds,
  not timed out; its GDB process returned 255. No successful artifact.
- `no-copy-normal/`: carrying regular lifts explicitly resolves that allocation
  problem and completes the theorem and save, as recorded above.
- `small-fast-normal/`: a 128-node budget (instead of 1,024) performs many more
  ordinary conversion steps. Deliberately stopped after 316.80 seconds, exit
  143, while still checking conversion 770; this is not a timeout or assertion.
  The selected budget remains 1,024.
- `closure-syntax-no-copy/` and `closure-syntax-small/`: both pass, including
  negative tests for changed data, binder capture, opacity and universes.
- The first `ClosureSyntax` fixture needed an explicit `nat` binder annotation;
  the failed fixture is preserved under `closure-syntax/`.
- Initial `HigherOrderClosure` drafts used lambda/arrow-pattern rules that either
  did not parse or did not trigger in the old baseline kernel either. These
  failed baseline controls are preserved. The final fixture specifically tests
  **arity-zero higher-order substitutions**, the existing inspector case being
  narrowed by the repair, with positive and negative captured-binder cases.
  It passes both the baseline (`higher-order-zero-baseline/`) and clean worker
  (`validation-0xdvrudn/HigherOrderClosure/`).
