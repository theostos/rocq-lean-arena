From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 30.
Lean Import "Widths.lean-export".
Check Int8_minValue_div_neg_one.
Check Int16_minValue_div_neg_one.
Check Int32_minValue_div_neg_one.
Check Int64_minValue_div_neg_one.
