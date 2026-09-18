Inductive A := a.
Inductive B := b.
Register A as kernel.unit_like.

Definition equal_A (x y : A) : x = y := eq_refl _.
Goal forall x y : B, x = y.
Proof. intros x y; exact_no_check (eq_refl x). Fail Qed. Abort.

Definition before_B := 0.
Register B as kernel.unit_like.
Definition equal_B (x y : B) : x = y := eq_refl _.
Definition still_equal_A (x y : A) : x = y := eq_refl _.

Reset before_B.
Goal forall x y : B, x = y.
Proof. intros x y; exact_no_check (eq_refl x). Fail Qed. Abort.
Definition restored_A (x y : A) : x = y := eq_refl _.
Goal forall x y : nat, x = y.
Proof. intros x y; exact_no_check (eq_refl x). Fail Qed. Abort.
