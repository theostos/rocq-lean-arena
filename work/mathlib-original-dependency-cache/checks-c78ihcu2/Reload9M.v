From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Require Import MathlibTo9000000.
Goal forall A : Type, A -> A. Proof. intros A x. exact x. Qed.
