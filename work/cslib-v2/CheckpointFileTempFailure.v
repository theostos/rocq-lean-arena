From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
(* The launcher limits the worker's output files to one byte and ignores
   SIGXFSZ: packing must raise an I/O error and remove its scratch file. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/cslib-v2/checkpoint-compact-smoke.lean-export" 1 6.
