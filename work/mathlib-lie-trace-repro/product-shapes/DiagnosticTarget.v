From LeanImport Require Import Lean.
Require Import DiagnosticPrefix.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 120.
(* Diagnostic only: dependency proofs are abstracted, not validation. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-lie-trace-repro/Diagnostic.stream.lean-export" 247148 247149.
