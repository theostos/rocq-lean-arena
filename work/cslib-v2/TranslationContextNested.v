From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/nested_containers".
Check roseSize : forall A : Type, Rose A -> Nat.
Example nestedExample_computes : nestedExample = 2.
Proof. cbv. reflexivity. Qed.
Example nestedAuxExample_computes : nestedAuxExample = 2.
Proof. cbv. reflexivity. Qed.
Example nestedProdExample_computes : nestedProdExample = 3.
Proof. cbv. reflexivity. Qed.
Fail Definition wrong_nested : Logic.eq nestedExample (3 : Nat) := Logic.eq_refl _.
