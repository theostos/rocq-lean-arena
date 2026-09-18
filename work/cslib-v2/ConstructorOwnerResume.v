From LeanImport Require Import Lean.
Require Import ConstructorOwnerBase.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/constructor-owner-repro/ConstructorOwner.lean-export" 67 75.
Check repro : Token.
Check Box_inst1.
Fail Definition constructor_owner_resume_wrong : nat := repro.
