From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Require Import MathlibTo14000000.
Set Lean Line Timeout 120.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/mathlib.ndjson" 13626505 13626506.
(* Diagnostic only: the error is AFTER the checked import, to avoid spending
   another three minutes saving the 13M-prefix state during each probe.
   This file cannot produce a validated checkpoint or a successful exit. *)
Check diagnostic_stop_after_kernel_checked_import_13626505.
