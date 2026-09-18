# Recursive singleton-family conversion regression

The Mathlib loop stopped at line **22,058,937**,
`Std.Do.ExceptConds.and_eq_left`. Its last saved and freshly reloaded checkpoint
is `MathlibTo20000000`, in `../mathlib-alignment-5m-20260913-with-terminal`.

## Cause and repair

The theorem's pure branch uses reflexivity at `ExceptConds PostShape.pure`.
This type computes to `PUnit`, whose inhabitants are definitionally equal in
Lean. The local Lean kernel's `is_def_eq_unit_like` weak-head normalizes the
inferred operand type before testing singleton eligibility
(`_deps/lean4-src/src/kernel/type_checker.cpp`).

Our bounded Rocq type-inspection code instead rejected every raw `Fix` and
closure `FFix`, preventing it from exposing this recursively defined type.
`Native.v` reproduces that rejection without the importer. The previous worker
fails it (`native-baseline/result.json`); the repaired worker passes it.

This repair changes only the production implementation in
`_worktrees/rocq/compact-peano-view/kernel/cClosure.ml`:

- Permit ordinary structural fixpoint reduction inside isolated type inspections.
- Validate mutual-fixpoint vector lengths, the selected body index and recursion
  argument indices before indexing them.
- Precharge vector sizes and application prefixes before ordinary fixpoint
  helpers traverse or allocate them. Recursive reduction consumes the same
  shared, finite inspection allowance.
- Keep unsupported cofixpoint and inversion execution excluded. No opacity,
  singleton-registration, complete-type, parameter or universe check is relaxed.

The ordinary reducer's behavior and all public interfaces remain unchanged.
This is a general computed-type repair, not a special case for this declaration
or an assertion that all Lean/Rocq conversion behavior is now identical.

## Reproduction and validation

`make-slice.py` extracts the target's 4,525-record dependency closure from the
pinned Mathlib NDJSON and retains **every dependency proof** (zero abstracted).
`slice.json` pins the original export, extraction/conversion tools and outputs.
`Slice.v` imports it with fail-on-error and without parsing-only or lazy mode.

Worker:
`11acf90892e197e1f4a61ac756906b59225e35189d837c223786266bb400f15c`

Independent checker:
`fa129d2d059ef132fcdf6e9e3ba767a85bbd8b1dc596c4cd52cdd445ba450b99`

Completed target replay: `slice-candidate/result.json`, **5.99 seconds**.
The independent checker also accepted the whole target closure in **81.17
seconds**, with no admitted dependencies (`compatibility-independent-final.json`).
The native regression fixture `unit_like_recursive_families.v` covers local
and named variables, both equality orientations, nested recursion, parameters,
and rejection for relevant fields, neutral branches and opaque families.
Private `closure_snapshot.ml` tests also cover malformed/oversized fixpoints,
fuel exhaustion (including divergence), frozen closures and caller immutability.

Broader gates and independent rechecks are recorded in:

- `../kernel-alignment-pass/final-gates-except-conds-2/`: runtime tests, 15 native
  fixtures, 20 legacy fixtures, fresh checkpoint/reload smoke, 44 importer tests
  and the runner test suite.
- That gate's `independent-check.json` and `strict-independent-check.json`:
  native proof rechecks, with explicit UIP opt-in for the strict profile.
- `slice-candidate/compatibility-independent-final.json`: independent checking
  of the complete target proof closure, without admitted dependencies.
- `../kernel-alignment-pass/strict-checker-except-conds/passed.json`: strict
  checker policy controls.

All validation gates completed successfully. Both independent native rechecks
accepted all 15 fixtures (2.12 seconds in compatibility mode, 2.10 seconds in
strict mode with explicit UIP). All 11 strict policy controls passed. The clean
broad rerun passed all 44 importer fixtures and all 206 runner tests (204 passed,
two opt-in skips), as well as the native/runtime/legacy and checkpoint gates.
The initial broad gate (`final-gates-except-conds`) passed all compiler fixtures
but failed five runner tests because their mocked supervisor paths depended on
an old, legitimately deleted foundation build. The runner tests now create
their own temporary foundation/worker/plan stubs; no production runner changed.
The gate also pins its runner test sources. The full suite is rerun in a new
directory; the initial attempt is not relabeled as successful.
The initial independent-check attempt (`compatibility-independent.json`) was
refused with exit 75 because another guarded test owned the single heavyweight
scope; its record is retained. The final attempt is run sequentially.

The importer still uses its existing elimination-relaxed compatibility profile.
The full imported slice is therefore not a strict-profile certification of
Mathlib. No imported proof or dependency was admitted or replaced to obtain the
pass, and this repair does not change that compatibility profile.

## Resume and progress

After validation, `resume.py` verifies the success records and their pinned
inputs, then launches `rocq-mathlib-alignment-5m-except-conds.service` with explicit
approval for the new worker hash. The existing launcher verifies the checkpoint
chain and reloads 20M with that worker before continuing at **20,000,001**.
Producer seals and previous failure logs are not rewritten. No checkpoint is
deleted. The run retains 5M intervals, 1,800 seconds per declaration, a single
16-GiB/no-swap worker, and disk safeguards; it stops on failure.

Resume was launched on **2026-09-14 at 00:19 CEST** (22:19 UTC on September 13).
The systemd service is active. `resume-approval.json` pins the successful gates
and the exact worker/checker inputs. The new attempt is
`../mathlib-alignment-5m-20260913-with-terminal/attempts/20260913T221945541382Z`.
Startup first verifies the saved prefix, then reloads `MathlibTo20000000`;
the full Mathlib continuation has not yet been certified complete.
At the final startup check (00:21 CEST), the repaired worker was actively
reloading `MathlibTo20000000Reload` under the 16-GiB/no-swap guard. The service
was active, with one Rocq worker. Assistant monitoring ends at that check.

```sh
python3 scripts/mathlib_ndjson_loop.py status --directory work/mathlib-alignment-5m-20260913-with-terminal
tail -F work/mathlib-alignment-5m-20260913-with-terminal/latest/MathlibTo25000000.run.log
journalctl --user -fu rocq-mathlib-alignment-5m-except-conds.service
```

The status command reports the actual log during checkpoint reload and for
subsequent chunks. No assistant monitoring is planned after confirming startup.
