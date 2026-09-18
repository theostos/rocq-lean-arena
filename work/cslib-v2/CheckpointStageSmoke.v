From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/checkpoint-compact-smoke.lean-export" 1 9.
Definition checkpoint_stage_eq : Logic.eq CheckpointReloadedProp CheckpointSavedProp := Logic.eq_refl _.
Fail Definition checkpoint_stage_wrong_eq : Logic.eq CheckpointReloadedProp nat := Logic.eq_refl _.
