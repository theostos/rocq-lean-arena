From LeanImport Require Import Lean.
Require Import CheckpointIndexedFromV1.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/checkpoint-compact-smoke.lean-export" 9 9.
Definition indexed_reloaded_eq : Logic.eq CheckpointReloadedProp CheckpointFileBase.CheckpointSavedProp := Logic.eq_refl _.
Fail Definition indexed_reloaded_wrong : Logic.eq CheckpointReloadedProp nat := Logic.eq_refl _.
