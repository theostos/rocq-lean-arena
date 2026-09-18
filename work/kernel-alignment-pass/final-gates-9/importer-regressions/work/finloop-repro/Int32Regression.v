From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 600.
Lean Import "../int32-tdiv-repro/Int32Tdiv.lean-export".
Check Int32_ofInt_tdiv.
