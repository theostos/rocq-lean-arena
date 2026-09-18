From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/dependent_sprop_projection".
Check subtypeSPropProperty.
Fail Definition wrong_projection (A : SProp) (p : A -> SProp) (s : Subtype_inst1 A p) : nat :=
  subtypeSPropProperty A p s.
