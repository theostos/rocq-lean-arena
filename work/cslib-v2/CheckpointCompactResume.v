From LeanImport Require Import Lean.
Require Import CheckpointCompactBase.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/checkpoint-compact-smoke.lean-export" 6 9.
Check CheckpointReloadedProp : Type.
Definition checkpoint_reload_eq : Logic.eq CheckpointReloadedProp CheckpointSavedProp := Logic.eq_refl _.
Fail Definition checkpoint_wrong_eq : Logic.eq CheckpointReloadedProp nat := Logic.eq_refl _.
