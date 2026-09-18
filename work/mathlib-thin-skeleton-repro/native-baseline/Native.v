Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Set Definitional UIP.
Record ProofBox (P : SProp) : Type := proof_box { proof_value : P }.
Register ProofBox as kernel.unit_like.
Record Box (A : Type) := box { value : A }.
Record Trans (P : nat -> SProp) := trans {
  app : forall n, Box (ProofBox (P n))
}.
Inductive EqS (A : Type) (x : A) : A -> SProp := rfl : EqS A x x.
Definition transport (A : Type) (x y : A) (e : EqS A x y) (B : Type) (v : B) : B :=
  match e with rfl _ _ => v end.

Goal forall A (x y : A) (e : EqS A x y) P (p : forall n, P n) (t : Trans P),
  transport A x y e (Trans P) t = trans P (fun n => box _ (proof_box (P n) (p n))).
Proof. intros A x y e P p t.
  exact_no_check (eq_refl (trans P (fun n => box _ (proof_box (P n) (p n))))). Qed.
