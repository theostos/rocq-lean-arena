# Padic conversion timeout — 2026-09-18

Production stopped at NDJSON line **54,302,445**,
`PadicInt.coe_adicCompletionIntegersEquiv_apply`, in the 50M–55M chunk.
Attempt: `../mathlib-alignment-5m-20260913-with-terminal/attempts/20260918T001051820999Z`.
The declaration reached its existing 1800-second limit. The guarded peak was
16,821,904 KiB, below the authorized 25-decimal-GB cap. The sealed 50M cursor
remains intact. There is no completed 55M checkpoint.

## Reproducer and current status

`prepare.py` extracts the exact theorem and its complete dependency closure,
using the existing slicer and NDJSON-to-legacy-stream converter. `slice.json`
binds the original export, tools and both output formats. It retains 2,636,968
NDJSON records and abstracts **zero** dependency proofs. The converted target
range is `[2636964, 2636965)`.

`PadicPrefix.v` checks every retained dependency proof. `PadicTarget.v` imports
only the exact theorem after requiring that prefix, with the normal 1800-second
limit and Fail mode. `PadicDiagnostic.v` is a separately labelled 120-second
observational replay; its cutoff is not production validation.

`run.py` reuses the guarded serial replay harness. `check.py` checks the target
artifact with `rocqchk -norec`, explicitly reusing its separately compiled
dependency prefix, foundation and stdlib. It is not an independent check of
all Mathlib or of the whole prefix.

Baseline worker:
`ed7e25350e150a2d2eca568d98975473e091930e9c053ae23dcd99c70eeab1d3`.
Baseline consumer: `../kernel-alignment-pass/importer.OJ3rkMcY`.
`conversion-baseline.ml` and `rocqworker-baseline.exe` preserve the production
state, including the previous computed-singleton-discriminant fix.

## Diagnosis and repair

The isolated trace identifies cast inversion inside optional symbolic congruence
recovery. The nested conversion callback did not inherit its enclosing strategy's
work allowance, so a nominally bounded trial could perform millions of steps.
Sharing that allowance alone was insufficient: ordinary conversion could still
enter expensive cast evaluation from speculative symbolic recovery.

The repair has two parts, limited to `cClosure.ml`, its interface, and
`conversion.ml`:

- Carry the enclosing strategy counter through reduction into nested inversion
  conversion. Exhaustion propagates to the strategy owner; it is not an equality
  verdict. No allowances or timeouts were increased.
- Keep inverted cases symbolic during optional symbolic recovery. Existing case
  congruence may compare them structurally; otherwise ordinary reduction checks
  inversion in full. Do not mark a temporarily deferred closure as neutral.

Constant and non-injective motives retain Rocq's existing inversion semantics.
The importer source and all previous kernel fixes remain intact; the importer
was rebuilt only for the changed kernel ABI.

Lean's pinned `reduce_recursor`/`to_cnstr_when_K` uses the same type checker's
definitional-equality callback to validate K reduction. This fix is an adaptation
to Rocq's closure machine and speculative strategies, not a claim that Lean has
an identical symbolic mode or cast representation.

## Completed validation

- Proof-preserving dependency prefix: exit 0, 1940.57 s, peak 1,731,592 KiB.
- Baseline isolated target: reproduced timeout at the diagnostic 120 s cutoff.
- Candidate normal target: exit 0, about **11.65 s declaration CPU**, 80.68 s
  including loading and writing, peak 979,552 KiB. Normal 1800 s limit retained.
- Independent target check: exit 0, 25.29 s, peak 536,064 KiB
  (`candidate-target/independent-retry.json`). Dependencies are reused, not
  rechecked by this invocation. The first check exited 137 during the VS Code
  restart, without a kernel error; its logs are preserved separately.
- **16** focused native fixtures passed, including positive and negative casts,
  unit-like types, projections, eta and congruence-budget tests.
- Direct checked-term unit passed: inherited work, exhaustion propagation,
  symbolic deferral, same-cell ordinary retry; 32 existing projected-major unit
  cases also passed (`inversion-unit-6.log`).

The full suite and the two additional exact historical replays in the optional
`regressions.py` script were not run. A full Mathlib pass is not yet established.

Validated worker:
`484cb306cb0f5d114071d601202a45c93de9c7ee803bbcd5c455553a6863649a`.
Consumer: `../kernel-alignment-pass/importer.rEXkanSl`.
`resume.py release` binds the completed evidence and current source diff into a
new consumer certificate before launching the continuation; old seals are not
edited.

Reference for comparison: the export pins Lean commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740`, especially
[`type_checker.cpp`](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp)
(`lazy_delta_reduction_step`, `lazy_delta_proj_reduction`, `is_def_eq_core`).

The intended continuation retains the original serial importer, 50M checkpoint,
5M intervals, 1800 seconds/declaration, 25-decimal-GB cap, 2 GiB reserve and no
swap. No proof skipping, old-seal changes, timeout increases or full-suite run.
