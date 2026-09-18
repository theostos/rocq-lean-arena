From LeanImport Require Import Lean.
Require Import CslibTo3500000.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Set Lean Line Timeout 600.

Redirect "CslibTo3808374.log"
  Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 3500000 3808374.
