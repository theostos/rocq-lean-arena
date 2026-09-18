# ThinSkeleton conversion regression — 2026-09-13

The existing `mathlib-alignment-5m-20260913-with-terminal` run stopped at NDJSON
line **12,973,729**, `CategoryTheory.ThinSkeleton.map₂._proof_1`. Its last sealed,
freshly reloaded checkpoint was **10,000,000**. This repair resumes that chain;
it does not start another line-1 generation or rewrite its producer seals.

## Reproduction and cause

`make-slice.py` extracted 26,869 records from the pinned reference export and
retained **all dependency proofs** (`abstracted 0`). `slice.json` records source
and output hashes. The original worker `938cf20b…` rejects the resulting proof
in 15.60 s (`slice-baseline/result.json`).

The failed conversion compares a transported natural transformation with the
identity transformation. Record eta and function eta leave a suspended equality
inversion followed by application/projection frames and a one-binder shift.
The singleton rule correctly requires both operands' complete types. But its
type-witness reconstruction tried to quote the whole inversion, then its delayed
return type, to perform this shift. Bounded quotation could not reconstruct those
large/partly erased closures. It therefore returned “inconclusive” and rejected
the theorem. Once shifting stayed delayed, exhausted quotation also incorrectly
prevented traversing the remaining argument spine.

## Final kernel change

Only `kernel/conversion.ml` changed for this repair; public interfaces,
declaration formats, importer sources and compatibility flags are unchanged.

* Keep the existing bounded, canonical relocation for quotable small terms.
* If it is unavailable, a **uniform shift** of a syntax closure shifts its
  substitution; a suspended inversion keeps an ordinary delayed shift wrapper.
  Neither path expands the proof, executes the inversion, or lifts an arbitrary
  constructor graph. Unsupported shapes/relocations still decline.
* Separate the single shared 4,096-occurrence quotation allowance from the
  4,096-element frame/argument allowance. Charge application arrays before
  copying them. Isolated snapshot copying and head reduction keep their separate
  shared 4,096-step bound.

No equality shortcut was added. Registration eligibility, complete-type
conversion (including parameters and universes), projection transparency, and
the prohibition on executing inversion cases inside inspection remain in place.
This repairs the representation used to attempt an existing equality check;
it is not a claim that all Lean/Rocq judgmental equalities are now identical.

## Validation records

Final worker:
`27e6a824c34bf8256a73e778023f78ed2061b573a51afc6653151cf59f800bc8`

Final independent checker:
`79ad54a5485e2d4c5001347a45cc396bcb8a5bdd7b0d6fe92a889cec6ee50971`

* `slice-final/result.json`: all-proof replay passes in 16.79 s.
* `native-final/result.json`: dependent singleton-valued function fields,
  transport with proof arguments, multiple eta binders, and relevant-data
  negative controls pass.
* `witness-tests-3.log`: private shift-reference comparisons, immutability,
  a linear DAG with over 2^50 expanded leaves, exhausted-quotation continuation,
  and oversized-interface rejection pass, alongside the existing witness tests.
* Integrated gate: `../kernel-alignment-pass/final-gates-21/`.
* Independent complete-slice recheck: `slice-final/compatibility-independent.json`.
* Independent native rechecks: the gate's `independent-check.json` and
  `strict-independent-check.json` (strict with explicit definitional-UIP opt-in).
* Strict policy controls: `../kernel-alignment-pass/strict-checker-6/`.

All these gates/rechecks completed successfully. The complete-slice independent
recheck took 81.19 s; all 14 native artifacts passed independent compatibility
checking in 2.11 s and strict checking with explicit UIP in 1.79 s. All 44
importer fixtures and 206 runner tests passed (two runner tests skipped).
`resume.py` verified these success records and their pinned inputs before launch.

The importer still uses its pre-existing elimination-relaxed compatibility
profile. The full exported proof replay is therefore **not** certification under
the independent checker's strict profile. This repair neither changes that
profile nor admits/abstracts dependency proofs to obtain a pass.

## Resume and progress

After validation, `python3 work/mathlib-thin-skeleton-repro/resume.py` launches
`rocq-mathlib-alignment-5m-20260913-thin-skeleton.service` with an explicit hash
approval for this kernel-only migration. The existing launcher validates the
sealed prefix, reloads 10M with the new worker, and continues at **10,000,001**.
It retains 5M checkpoint intervals, a 1,800-second declaration limit, one
16-GiB/no-swap guarded worker, and disk-space safeguards. It stops on failure.

```sh
python3 scripts/mathlib_ndjson_loop.py status --directory work/mathlib-alignment-5m-20260913-with-terminal
tail -f work/mathlib-alignment-5m-20260913-with-terminal/latest/MathlibTo15000000.run.log
journalctl --user -fu rocq-mathlib-alignment-5m-20260913-thin-skeleton.service
```

The status file gives the current chunk's actual log after 15M. Its automated
progress writer/debugger does not use a model. No assistant monitoring is planned
after confirming resume startup. No earlier checkpoints were deleted.

Cleanup removed only this repair's 46 completed temporary test executables
(418,336,696 bytes, about 399 MiB). The exact paths and hashes are recorded in
`cleanup-test-executables.json`; their sources, compiled objects and logs remain
available for regeneration. No proof artifact or checkpoint was removed.
