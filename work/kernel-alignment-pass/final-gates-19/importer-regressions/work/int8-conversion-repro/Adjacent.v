From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 30.
Lean Import "Adjacent.lean-export".
Check Int16_toBitVec_not.
Check Int32_toBitVec_not.
Check Int64_toBitVec_not.
Check ISize_toBitVec_not.
Check Int8_toBitVec_and.
Check Int8_toBitVec_or.
Check Int8_toBitVec_xor.
