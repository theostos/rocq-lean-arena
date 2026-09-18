From LeanImport Require Import Lean.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 600.

(* Start with an empty importer state and read the entire fixed export to EOF.
   Do not require any earlier cslib checkpoint: their full snapshots accumulate
   in memory. This run still uses the experimental kernel, not upstream Rocq. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export".
