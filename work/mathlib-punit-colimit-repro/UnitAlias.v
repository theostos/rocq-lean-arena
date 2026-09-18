Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record ProofBox (P : SProp) : Type := box { unbox : P }.
Register ProofBox as kernel.unit_like.
Definition Wrap (A : Type) := A.

Goal forall (P : SProp) (x y : ProofBox P), x = y.
Proof. intros P x y. exact_no_check (eq_refl x). Qed.
Goal forall (P : SProp) (x y : Wrap (ProofBox P)), x = y.
Proof. intros P x y. exact_no_check (eq_refl x). Qed.
