From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Require Import MathlibTo1000000.

Print PUnit.
Print CategoryTheory_Discrete_inst1.
Print CategoryTheory_discreteCategory_inst1.
Print Hom0.

Goal forall x y : PUnit, Lean.eq x y.
Proof. intros x y. exact_no_check (Lean.eq_refl x). Qed.
