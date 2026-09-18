From LeanImport Require Import Lean.
Require Import CslibTo5500000.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Set Lean Line Timeout 600.

Redirect "CslibTo5534591.log"
  Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 5500000 5534591.
