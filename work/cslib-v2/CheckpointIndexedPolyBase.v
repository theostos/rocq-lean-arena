From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/checkpoint-indexed-poly.lean-export" 1 14.
Check PolyId.
Fail Check PolyId_inst1.
Fail Definition indexed_poly_wrong : nat := PolyId.
