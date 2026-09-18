From LeanImport Require Import Lean.
Require Import CslibCompactTo8500000.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Set Lean Line Timeout 600.
Redirect "CslibCompactTo8750000.log" Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 8500000 8750000.
