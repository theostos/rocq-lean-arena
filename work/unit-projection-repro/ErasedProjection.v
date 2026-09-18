Set Primitive Projections.
Inductive U := unit_value.
Register U as kernel.unit_like.
Inductive Proof : SProp := proof.
Record Box (p : Proof) := box { value : U }.
Axiom make1 make2 : forall p : Proof, Box p.
Definition erased_parameter (p q : Proof) :
  value p (make1 p) = value q (make2 q) := eq_refl _.

Record NatBox (p : Proof) := nat_box { nat_value : nat }.
Axiom make_nat1 make_nat2 : forall p : Proof, NatBox p.
Fail Definition different_nat_fields (p q : Proof) :
  nat_value p (make_nat1 p) = nat_value q (make_nat2 q) := eq_refl _.
