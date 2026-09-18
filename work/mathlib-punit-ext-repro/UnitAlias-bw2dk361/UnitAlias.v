Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record ProofBox (P : SProp) : Type := box { unbox : P }.
Register ProofBox as kernel.unit_like.
Definition Wrap (A : Type) := A.

Definition direct (P : SProp) (x y : ProofBox P) : x = y := eq_refl x.
Definition wrapped (P : SProp) (x y : Wrap (ProofBox P)) : x = y := eq_refl x.
