(* A transparent alias in a type family's discriminant must reduce before
   deciding whether the family instance is unit-like. *)
Inductive U := unit_value.
Register U as kernel.unit_like.

Definition bool_alias (b : bool) := b.
Definition family (b : bool) : Type := if b then U else nat.

Goal forall f g : family (bool_alias true), f = g.
Proof. intros f g. exact_no_check (eq_refl f). Qed.
