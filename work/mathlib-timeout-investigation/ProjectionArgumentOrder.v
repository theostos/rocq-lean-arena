Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Record Box (A : Type) := box { run : nat -> nat; unused : A }.
Arguments box {A} _ _.
Arguments run {A} _ _.

Fixpoint duplicate (n : nat) : nat :=
  match n with O => O | S k => Nat.add (duplicate k) (duplicate k) end.

Definition pack (A : Type) (a : A) : Box A := box (fun n => n) a.

Goal forall n, run (pack nat (duplicate 32)) n = run (pack bool true) n.
Proof. intro n; exact_no_check (eq_refl (run (pack nat (duplicate 32)) n)). Timeout 5 Qed.

Goal forall n, run (pack bool true) n = run (pack nat (duplicate 32)) n.
Proof. intro n; exact_no_check (eq_refl (run (pack bool true) n)). Timeout 5 Qed.

Goal run (pack nat 0) 1 = run (pack bool true) 0.
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.

Definition sealed (A : Type) (a : A) : Box A.
Proof. exact (pack A a). Qed.

Goal run (sealed nat 0) 1 = 1.
Proof. exact_no_check (eq_refl 1). Fail Qed. Abort.
