# Unit-valued projection conversion

**Latest follow-up:** the launcher now also pins the [direct-dependency fix](../hashmap-unit-cons-repro/README.md)
for `Std.HashMap.unitOfList_cons` and the [compact-fuel fix](../int32-min-div-repro/README.md)
for `Int32.minValue_div_neg_one`.
The artifact hashes below document the earlier unit-projection-only worker.

**Follow-up:** the first projection patch regressed at cslib line 11,409,934
(`LinearMap.exists_ne_zero_of_sSup_eq`), with an assertion in `cClosure.ml:872`.
The correction below replaces eager argument reconstruction with lazy
substitution. The resume command is unchanged and now pins the corrected worker.

The resumed cslib import failed at line **12,283,082**, on
`LawfulMonadStateOf.modify_eq`. This was a checking error, not an OOM.

The equality chain needs these functions to be definitionally equal:

```lean
example {α : Type} (z : PUnit × α) :
    (fun k : PUnit => k) = (fun _ : PUnit => z.1) := rfl
```

## Change

Only `kernel/conversion.ml` changes runtime behavior. The existing registered
unit-eta type inspection previously rejected projection stacks. It now follows
applications and projections, instantiates record parameters and inspects the
resulting type. Cases, fixpoint eliminations and primitive-operation stacks
remain excluded.

The projection traversal uses a placeholder for the record value. The new
unit query therefore rejects projection types that mention that value
(`Vars.noccurn 1`); it does not guess dependent field types. Existing non-unit
uses of the traversal retain their previous behavior. This is not complete
support for every dependent unit-valued projection.

Record parameters remain conversion closures during substitution. In particular,
proof arguments may already contain the kernel's `FIrrelevant` marker, which
cannot be reconstructed as a source term. The first patch exposed an eager
`term_of_fconstr` traversal of those parameters; the corrected traversal uses
`usubs_cons` and `mk_clos`, leaving unused parameters untouched. The assertion
and the typing rules are not weakened to accommodate the error.

No importer, library proof, public kernel interface or serialization format was
changed. The experimental kernel's existing unit registration, arithmetic and
other extensions remain in use. These tests are not a soundness certification.

## Tests

- `export-linear-map.sh` exports the unchanged failing LinearMap proof and
  dependencies: **136,434 lines**. `LinearMap.baseline.*` reproduces the exact
  `cClosure.ml:872` assertion with the first projection worker.
  `LinearMap.lazy-substitution.*` passes all 1,993 entries and saves the result
  with the corrected worker (294,980 KiB peak). The saved module also reloads.
  The other files tagged `lazy-substitution` / `lazy-projection` record the
  follow-up checks. The canonical kernel test now also covers an irrelevant
  record parameter and rejects an arbitrary equality of its `nat` field.
  The ten selected importer regressions, FinLoop, the full Int32 dependency
  regression and the saved-prefix compatibility probe also pass again with
  the corrected worker. No full-library run was launched for this follow-up.

- `UnitProjection.baseline.*`: the standalone Rocq reproduction fails with the
  previous worker. `UnitProjection.candidate2.*` passes with the patched worker,
  including nested/applied projections, aliases and both comparison directions.
  Seven negative checks reject arbitrary equalities between ordinary fields,
  dependent fields, functions or records. The reusable regression is
  `test-suite/success/unit_like_projection.v` in the kernel worktree.
- `export.sh` checks the minimal Lean example and exports the original,
  unchanged `LawfulMonadStateOf.modify_eq` proof with its dependencies.
  This export is **3,852 lines**. `ModifyEq.baseline.*` fails at its final
  declaration with the same `Eq_trans` mismatch; `ModifyEq.candidate1.*` passes
  all 74 entries and saves the result. `ReloadModifyEq.candidate.*` reloads it
  and reports assumptions; there is no new theorem-specific axiom.
- `ImportedProjection.candidate.*` checks the minimal Lean export with upfront
  universe instantiation. All ten existing tests selected by
  `../finloop-repro/run-regressions.sh unit-projection` pass.
- The earlier FinLoop proof and the complete 233,043-line Int32 dependency
  regression both pass with this kernel. The bounded arithmetic positive and
  negative controls pass (`Arithmetic.candidate.*`). An attempted broader
  `compact_peano.v` test could not load the missing `Stdlib.NArith` module in
  this partial stdlib build; its failed setup log is preserved.
- `ReloadPrefix.candidate.*` loads the original **11,005,951** checkpoint and
  saves a dependent module successfully. Peak guarded memory: 1,464,400 KiB.
  The checkpoint and original manifests are unchanged. This establishes load
  compatibility, not fresh rechecking of all prefix proofs with the new kernel.

The kernel build was limited to 2 GiB, small proof tests to 4 GiB, and the
checkpoint compatibility test to 8 GiB. The shared guard permits one heavy job
at a time. No full-library continuation was launched as part of this fix.

## Resume manually

From the repository root:

```sh
bash work/unit-projection-repro/resume-cslib.sh
```

This starts an independent service, resuming from **11,005,951**, not the last
failure. It checks the remaining input, saves `Complete.vo`, then loads that
module in a fresh process. Memory limits are 16 GiB hard / 15 GiB preventive
RSS / 3 GiB system-available reserve, with no workload swap. Admission needs
19 GiB available. Only the guarded Rocq workload is stopped on memory pressure.

```sh
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

Stop the service using `systemctl --user stop SERVICE_NAME`, with the name
printed by the launcher. No model monitoring is necessary.

The migration permits exactly the tested new worker hash. It validates the
pinned historical prefix/manifests and every other original input, preserves
them, and records a separate `migration.sha256` for each new attempt. It does
not bypass Rocq's library digest checks. The old launcher intentionally still
expects the old worker; use the command above for this migration.

The compatibility probe and all commands it uses have passed; the new full-run
service wrapper has been syntax-checked, not launched end-to-end. Full cslib
completion is still unproven. A fresh complete pass with the final toolchain
remains necessary for final validation.

## Artifact hashes

```text
worker:       8c924251187f15b14a529758a8b1e67d6fd48ac691b69539699c14e2c3a41bb1
plugin:       93f048367978e9d36bc8f79831eea0ce3b4dac5104297c843ffe95bfa13aec07
foundation:   de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b
Prefix.vo:    6a81ed1a0fc51ca41e16f24972dc746b7cd4b38a6673a8e4c37f30eb5b17f91b
ModifyEq dump: fc4206b34b01d7e43ea38fa2217294b17dfee27fe558c5b0a5a7d8356556f63f
ModifyEq.vo:   f73a4747e1ef0bbcf9c633eb1f8bb250669f3f5e25b0c25786d59f4241ee2a9f
LinearMap dump:3458e6485d5d36a5e3bba47de3ccba99f7b29abbee610f27d3d956c6bd9f0f27
LinearMap.vo:  eacb541667cad0a54eea0690b25b33696b042b2784658a9d4d1c846c36a10a4e
```

Historical first-projection worker (the regressing version):
`5296f8231deaa69bc66400ed0c51e0fc278fa654072b8322a9051f8271a9c457`.
