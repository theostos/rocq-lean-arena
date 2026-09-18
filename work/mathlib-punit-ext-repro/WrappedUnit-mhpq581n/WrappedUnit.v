Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record ProofBox (P : SProp) : Type := proof_box { proof_value : P }.
Register ProofBox as kernel.unit_like.
Record Box (A : Type) := box { value : A }.

Goal forall (P : SProp) (x y : Box (ProofBox P)), x = y.
Proof. intros P x y. exact_no_check (eq_refl x). Qed.

Goal forall (P : SProp) (f : nat -> Box (ProofBox P)) x y, f x = f y.
Proof. intros P f x y. exact_no_check (eq_refl (f x)). Qed.

Goal forall (P : SProp) (x y : Box (Box (ProofBox P))), x = y.
Proof. intros P x y. exact_no_check (eq_refl x). Qed.

Goal forall (x y : Box nat), x = y.
Proof. intros x y. exact_no_check (eq_refl x). Fail Qed. Abort.

Goal forall (f : nat -> Box nat) x y, f x = f y.
Proof. intros f x y. exact_no_check (eq_refl (f x)). Fail Qed. Abort.

Record Mixed (P : SProp) := mixed { proof_part : ProofBox P; number : nat }.
Goal forall (P : SProp) (x y : Mixed P), x = y.
Proof. intros P x y. exact_no_check (eq_refl x). Fail Qed. Abort.

Record Dependent := dependent { field_type : Type; field_value : field_type }.
Goal forall (x y : Dependent), x = y.
Proof. intros x y. exact_no_check (eq_refl x). Fail Qed. Abort.
