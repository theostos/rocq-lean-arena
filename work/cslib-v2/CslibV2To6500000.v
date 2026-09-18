From LeanImport Require Import Lean.
Require Import CslibV2To6000000.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 600.

(* Keep the two isolated regression checkpoints out of the canonical ancestry:
   each ancestor otherwise retains another complete packed importer state. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 6000000 6500000.
