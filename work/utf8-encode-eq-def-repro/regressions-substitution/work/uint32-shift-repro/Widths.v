From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 30.
Lean Import "Widths.lean-export".
Check UInt8_toUInt16_shiftLeft_of_lt.
Check UInt8_toUInt32_shiftLeft_of_lt.
Check UInt8_toUInt64_shiftLeft_of_lt.
Check UInt16_toUInt32_shiftLeft_of_lt.
Check UInt16_toUInt64_shiftLeft_of_lt.
Check UInt32_toUInt64_shiftLeft_of_lt.
