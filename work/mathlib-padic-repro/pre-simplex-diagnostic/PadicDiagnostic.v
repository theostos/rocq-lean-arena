From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
(* A short observational replay, not the production/validation deadline. *)
Set Lean Line Timeout 120.
Require Import PadicPrefix.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-padic-repro/Padic.lean-export" 2636964 2636965.
