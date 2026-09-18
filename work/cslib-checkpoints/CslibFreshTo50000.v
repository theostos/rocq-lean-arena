From LeanImport Require Import Lean.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Set Lean Line Timeout 600.

Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export" 0 50000.

Check UInt32_isValidChar : UInt32 -> SProp.
Check UInt32_toNat : UInt32 -> Nat.
