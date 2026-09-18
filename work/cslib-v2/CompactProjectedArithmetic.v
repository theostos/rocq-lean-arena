From LeanImport Require Import Lean.

Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Inductive SignedNat := Pos : Nat -> SignedNat | Neg : Nat -> SignedNat.

Definition power x n :=
  match x with
  | Pos a => Pos (Nat_pow a n)
  | Neg a => Neg (Nat_pow (Nat_succ a) n)
  end.

Definition multiply x y :=
  match x, y with
  | Pos a, Pos b => Pos (Nat_mul a b)
  | Pos a, Neg b => Neg (Nat_mul a (Nat_succ b))
  | Neg a, Pos b => Neg (Nat_mul (Nat_succ a) b)
  | Neg a, Neg b => Pos (Nat_mul (Nat_succ a) (Nat_succ b))
  end.

Record PowerOps := { get_power : SignedNat -> Nat -> SignedNat }.
Record MultiplyOps := { get_multiply : SignedNat -> SignedNat -> SignedNat }.
Definition power_ops := {| get_power := power |}.
Definition multiply_ops := {| get_multiply := multiply |}.

Strategy 1 [power_ops power].
Strategy -1 [multiply_ops multiply].

Definition n2 := BinNat.N.pos (BinNums.xO BinNums.xH).
Definition n31 := BinNat.N.pos
  (BinNums.xI (BinNums.xI (BinNums.xI (BinNums.xI BinNums.xH)))).
Definition n32 := BinNat.N.pos
  (BinNums.xO (BinNums.xO (BinNums.xO (BinNums.xO (BinNums.xO BinNums.xH))))).

Example projected_power_step :
  get_power power_ops (Pos (CompactNat n2)) (CompactNat n32) =
  get_multiply multiply_ops (Pos (CompactNat n2))
    (get_power power_ops (Pos (CompactNat n2)) (CompactNat n31)).
Proof. reflexivity. Qed.

Fail Definition projected_unequal_power_step :
  get_power power_ops (Pos (CompactNat n2)) (CompactNat n32) =
  get_multiply multiply_ops (Pos (CompactNat n2))
    (get_power power_ops (Pos (CompactNat n2)) (CompactNat n32)) :=
  eq_refl _.
