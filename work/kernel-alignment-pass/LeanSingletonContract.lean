import Init

structure ContractProofBox (P : Prop) : Type where
  proof : P

structure ContractBox (A : Type) : Type where
  value : A

set_option debug.skipKernelTC false

-- The direct reflexivity probe in LeanUnitProbe.lean is rejected, but the
-- corresponding propositional equality is provable by ordinary elimination.
-- This is not a conservativity proof for a general conversion extension.
theorem contractBoxUnique (P : Prop) (x y : ContractBox (ContractProofBox P)) : x = y := by
  cases x with
  | mk x =>
    cases y with
    | mk y =>
      cases x
      cases y
      rfl

#print axioms contractBoxUnique
