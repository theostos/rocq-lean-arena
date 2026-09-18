From LeanImport Require Import Lean.
Set Debug "backtrace".
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 60.
Lean Import "LinearMap.lean-export".
Check LinearMap_exists_ne_zero_of_sSup_eq.
