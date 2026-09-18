Inductive U := unit_value.
Register U as kernel.unit_like.
Definition family (b : bool) : Type := if b then U else nat.

Goal forall f : family true, f = unit_value.
Proof. intro f. exact_no_check (eq_refl unit_value). Qed.
