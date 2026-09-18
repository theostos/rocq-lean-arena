# Nullary unit recursor regression

The September 7 full pass stopped at line **11,005,951** on
`Cslib.Automata.NA.FinAcc.instTotalSumUnitFinLoopOfNonemptyElemStart`:
`Illegal application` of `Eq_trans`. This was not an OOM: guard exit 1,
cgroup peak 2,003,408 KiB, and no full `.vo` was produced.

## Cause and change

`LTS.totalize.match_1` contains a case split on an arbitrary `Unit` value.
Lean reduces that single-constructor case to its only branch. The imported
Rocq recursor retained a `match`, stuck on the variable. Consequently, the
intermediate propositions in the equality chain did not convert.

The importer now generates a branch-only eliminator for **registered,
unindexed unit-like types whose sole constructor has no fields**. It verifies
the expected generated scheme shape and asks the kernel to check the new body
against the original dependent scheme type. Indexed types and constructors
with fields retain their existing schemes. No cslib proof is rewritten.

This is an importer-only change. It uses the experimental kernel's existing
registered unit eta support; it does not establish stock-Rocq compatibility or
soundness of the inherited kernel extensions and elimination settings.

Small example from `NullaryUnit.lean`:

```lean
def unitMatch (x : Unit) : Nat := match x with | () => 37
theorem unitMatch_eq (x : Unit) : unitMatch x = 37 := rfl
```

## Evidence

- `export.sh` exports the unchanged original cslib theorem and dependencies:
  10,248 lines, 200,294 bytes; SHA-256
  `2915db4d71931ec28bc3bd8a82695ba54bd9807277e1db3fef18737169ff452a`.
- `FinLoop.baseline.*`: the original proof fails at the same equality
  application as the full pass (last entry, line 10,248).
- `FinLoop.guarded-candidate.*`: all 209 entries import, the target is checked,
  atomic `.vo` promotion, guard exit 0, peak 163,144 KiB.
- `FinLoopReload.candidate.*`: fresh reload and assumption inspection pass.
  Reported assumptions include definitional UIP, propositional extensionality,
  choice and quotient soundness, not a new axiom for this theorem.
- `NullaryUnit.old-scheme-control.*`: temporarily bypassing only the new
  scheme adapter reproduces failure at `choose_eq`, line 314.
- `NullaryUnit.final.*`: restoring the adapter passes, including upfront
  universe instantiation, dependent motives, parameterized units, and controls
  for relevant fields, multiple constructors and indexed types. Two deliberately
  incorrect equalities are rejected by `Fail Definition` checks.
- `Int32Regression.final.*`: fresh import of the original 233,043-line
  `Int32.ofInt_tdiv` dependency export passes; peak 289,468 KiB.
- All ten tests selected by `run-regressions.sh explicit-instances` pass.
  The first broader attempt exposed a stale test assumption in
  `dependent_sprop_projection.v`: it named an unused universe instance without
  requesting upfront instantiation. The fixture now requests it explicitly.

The reusable regression lives in the importer's `dumps/nullary_unit_scheme*`
and `tests/nullary_unit_scheme.v`, listed in `tests/_CoqProject`.

## Tested toolchain

- Unchanged worker: `93b97317727e726c7b27b45c829536fba090085832e508b99fff4d8b3aafe4d0`.
- Updated plugin: `93f048367978e9d36bc8f79831eea0ce3b4dac5104297c843ffe95bfa13aec07`.
- Unchanged foundation: `de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b`.

The full-library retry has **not** been started. See
[the manual full-run instructions](../cslib-full-fresh/CHECKPOINTED-RUN.md).
