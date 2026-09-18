From LeanImport Require Import Lean.
Require Import MathlibTo25000000.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
(* One continuous original-order import: avoid serializing the whole 25M
   environment between nearby targets. The 120-second per-declaration limit
   is stricter than the production 1800-second limit, including in the gaps. *)
Set Lean Line Timeout 120.
Time Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/mathlib.ndjson" 25000001 25525775.
