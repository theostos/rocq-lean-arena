Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Inductive U := tt.
Register U as kernel.unit_like.
Record Wrap (A : Type) := wrap { val : A }.
Definition Alias (A : Type) := Wrap A.
Definition Alias2 (A : Type) := Alias A.

Goal forall x y : Alias2 U, val _ x = val _ y.
Proof. intros x y. exact_no_check (eq_refl (val _ x)). Qed.

Goal forall x y : Alias2 nat, val _ x = val _ y.
Proof. intros x y. exact_no_check (eq_refl (val _ x)). Fail Qed. Abort.

Goal forall (A : Type) (x y : Alias2 A), val _ x = val _ y.
Proof. intros A x y. exact_no_check (eq_refl (val _ x)). Fail Qed. Abort.

Record DepPair := dep_pair { field_type : Type; field_value : field_type }.
Definition DepAlias := DepPair.
Goal forall (x : DepAlias) (y : field_type x), field_value x = y.
Proof. intros x y. exact_no_check (eq_refl (field_value x)). Fail Qed. Abort.

Goal forall x y : Alias U, val _ x = val _ y.
Proof. intros x y. exact_no_check (eq_refl (val _ x)).
Opaque Alias.
Fail Qed.
Transparent Alias.
Qed.
