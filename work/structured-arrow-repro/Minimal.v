Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Inductive U := tt.
Register U as kernel.unit_like.
Record Wrap (A : Type) := mkWrap { val : A }.

Definition unit_neutrals (x y : U) : x = y := eq_refl _.
Definition wrapped_constructor (x : Wrap U) : x = mkWrap U tt := eq_refl _.
Fail Definition wrapped_neutrals (x y : Wrap U) : x = y := eq_refl _.

Record Arrow := mkArrow { left : Wrap U }.
Definition Hom (x y : Wrap U) := val U x = val U y.
Definition identity (x : Wrap U) : Hom x x := eq_refl _.
Goal forall f g : Arrow, Hom (left f) (left g).
Proof. intros f g. exact_no_check (identity (left f)). Qed.
