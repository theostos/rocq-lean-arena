From Corelib Require Import Init.Datatypes Init.Logic.

Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

Inductive PNat := PZero | PSucc : PNat -> PNat.
Register PNat as kernel.ind_peano_nat.

Fixpoint pdouble n :=
  match n with
  | PZero => PZero
  | PSucc n => PSucc (PSucc (pdouble n))
  end.
Register pdouble as kernel.peano_nat_double.

Fixpoint padd n m :=
  match m with
  | PZero => n
  | PSucc m => PSucc (padd n m)
  end.
Register padd as kernel.peano_nat_add.

Fixpoint pmul n m :=
  match m with
  | PZero => PZero
  | PSucc m => padd (pmul n m) n
  end.
Register pmul as kernel.peano_nat_mul.

Fixpoint ppow n m :=
  match m with
  | PZero => PSucc PZero
  | PSucc m => pmul (ppow n m) n
  end.
Register ppow as kernel.peano_nat_pow.

Definition two := PSucc (PSucc PZero).
Definition five := PSucc (PSucc (PSucc two)).
Definition eighty := pdouble (pdouble (pdouble (pdouble five))).
Definition seventy_nine := match eighty with PZero => PZero | PSucc n => n end.

Inductive PInt := POfNat : PNat -> PInt | PNegSucc : PNat -> PInt.

Definition pint_pow value exponent :=
  match value with
  | POfNat n => POfNat (ppow n exponent)
  | PNegSucc n => PNegSucc (ppow (PSucc n) exponent)
  end.

Definition pint_mul left right :=
  match left, right with
  | POfNat n, POfNat m => POfNat (pmul n m)
  | POfNat n, PNegSucc m => PNegSucc (pmul n (PSucc m))
  | PNegSucc n, POfNat m => PNegSucc (pmul (PSucc n) m)
  | PNegSucc n, PNegSucc m => POfNat (pmul (PSucc n) (PSucc m))
  end.

Strategy 1 [pint_pow].

(* The wrapper path and the directly registered operation path both remain
   useful: these values cannot practically be expanded as unary naturals. *)
Definition closed_wrapper :
  pint_pow (POfNat two) eighty =
  pint_mul (POfNat two) (pint_pow (POfNat two) seventy_nine) := eq_refl _.

Definition registered_operations :
  ppow two eighty = pmul two (ppow two seventy_nine) := eq_refl _.

Fail Definition wrong_wrapper :
  pint_pow (POfNat two) eighty =
  pint_pow (POfNat two) seventy_nine := eq_refl _.

Fail Definition wrong_registered_operations :
  ppow two eighty = ppow two seventy_nine := eq_refl _.
