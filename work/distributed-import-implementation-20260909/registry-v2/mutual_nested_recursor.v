From LeanImport Require Import Lean.

Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/distributed-import/dumps/mutual_nested_recursor".

Check optionNestedExample : Nat.
Check mutualNestedExample : Nat.

Example optionNestedExample_computes : optionNestedExample = 3.
Proof. cbv. reflexivity. Qed.

Example mutualNestedExample_computes : mutualNestedExample = 4.
Proof. cbv. reflexivity. Qed.
