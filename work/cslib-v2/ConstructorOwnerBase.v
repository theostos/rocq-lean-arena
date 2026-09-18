From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/constructor-owner-repro/ConstructorOwner.lean-export" 1 67.
Check Box.
Fail Check Box_inst1.
Fail Definition constructor_owner_base_wrong : nat := Box.
