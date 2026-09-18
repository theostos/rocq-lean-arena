From LeanImport Require Import Lean.
Require Import CheckpointIndexedPolyBase.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/checkpoint-indexed-poly.lean-export" 14 19.
Check PropPolyId : forall (A : SProp), A -> A.
Check PolyId_inst1 : forall (A : SProp), A -> A.
Fail Definition indexed_prop_poly_wrong : nat := PropPolyId.
