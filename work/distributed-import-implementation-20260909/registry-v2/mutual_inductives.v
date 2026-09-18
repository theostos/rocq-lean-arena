From LeanImport Require Import Lean.

Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/distributed-import/dumps/mutual_inductives".

Check mutualExample : Nat.
Check mutualFoldTree : MutTree -> Nat.
Check MutTree0_recl.
Check MutForest0_recl.

Example mutualExample_computes : mutualExample = 2.
Proof. cbv. reflexivity. Qed.
