Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record Box := box { value : nat }.

Fixpoint duplicate (n : nat) : nat :=
  match n with O => O | S k => Nat.add (duplicate k) (duplicate k) end.
Definition computed (fuel x : nat) : Box :=
  match duplicate fuel with O => box x | S _ => box (S x) end.
Definition left (x : nat) := computed 32 x.
Definition right (x : nat) := computed 32 (id x).

Goal forall x, value (left x) = value (right x).
Proof. intro x; exact_no_check (eq_refl (value (left x))). Timeout 5 Qed.
Goal forall x, value (right x) = value (left x).
Proof. intro x; exact_no_check (eq_refl (value (right x))). Timeout 5 Qed.

Goal value (computed 2 0) = value (computed 2 1).
Proof. exact_no_check (eq_refl (value (computed 2 0))). Fail Qed. Abort.
