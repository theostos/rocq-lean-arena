(* Short diagnostic only: production and final validation retain 1800s. *)
From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 120.
Require Import CotangentStreamPrefix.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-cotangent-repro/Cotangent.lean-export" 2133792 2133793.
