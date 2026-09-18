From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 30.
Lean Import "Widths.lean-export".
Check UInt8_toInt8_not.
Check UInt16_toInt16_not.
Check UInt32_toInt32_not.
Check UInt64_toInt64_not.
Check USize_toISize_not.
