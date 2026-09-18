From LeanImport Require Import Lean.
Require Import Checkpoint.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 30.
Lean Import "UIntNot.lean-export" 22364.
Check UInt32_toInt32_not.
