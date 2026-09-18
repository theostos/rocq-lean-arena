Set Primitive Projections.
Inductive U := tt.
Register U as kernel.unit_like.
Record Wrap (A : Type) := mkWrap { val : A }.
Definition WrappedUnit := Wrap U.

Goal forall x y : Wrap U, val U x = val U y.
Proof. intros x y. exact_no_check (eq_refl (val U x)). Qed.

Goal forall x y : WrappedUnit, val U x = val U y.
Proof. intros x y. exact_no_check (eq_refl (val U x)). Qed.
