From LeanImport Require Import Lean.
Require Import MathlibTo30000000.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
(* Keep the production declaration order and one uninterrupted conversion
   environment through both reported Char failures and the enclosing theorem. *)
Set Lean Line Timeout 120.
Time Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/mathlib.ndjson" 30000001 30806241.
