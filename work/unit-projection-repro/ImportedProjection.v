From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Upfront Instantiation.
Set Lean Line Timeout 60.
Lean Import "UnitProjection.lean-export".
Check projected_identity.
Check two_projections.
Check nested_projection.
Check applied_projection.
