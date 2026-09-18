From LeanImport Require Import Lean.
Require Import CslibV2Blocker6231278.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 600.

(* Force the saved state, then serialize it without rechecking declarations. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 6231279 6231279.
