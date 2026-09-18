From LeanImport Require Import Lean.
Require Import Int32TdivPrefix.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 600.
Lean Import "Int32Tdiv.lean-export" 233043 233044.
Check Int32_ofInt_tdiv.
