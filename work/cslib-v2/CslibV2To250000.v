From LeanImport Require Import Lean.
Require Import CslibV2To50000.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Set Lean Line Timeout 600.

Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 50000 250000.
