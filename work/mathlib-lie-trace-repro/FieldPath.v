From LeanImport Require Import Lean.
Require Import ProofPrefix.
Set Kernel Conversion Dep Heuristic.
Set Printing Depth 80.
Set Printing Width 160.
Timeout 20 Definition field_path (k : Type) (F : Field k) :=
  let K := AlgebraicClosure k F in
  @eq_refl (Semiring K)
    (toSemiring K (toRing3 K (Field_toDivisionRing K (AlgebraicClosure_instField k F)))).
Timeout 20 Definition field_path_checked (k : Type) (F : Field k) :
  let K := AlgebraicClosure k F in
  Lean.eq
    (toSemiring K (toRing3 K (Field_toDivisionRing K (AlgebraicClosure_instField k F))))
    (toSemiring0 K (CommRing_toCommSemiring K (AlgebraicClosure_instCommRing k F)))
  := field_path k F.
