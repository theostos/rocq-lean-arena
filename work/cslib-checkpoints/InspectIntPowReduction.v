From LeanImport Require Import Lean.
Require Import CslibTo5402976.

Set Kernel Conversion Dep Heuristic.

Definition leanNat2 : Nat :=
  Nat_of_N (BinNat.N.pos (BinNums.xO BinNums.xH)).

Definition leanNat31 : Nat :=
  Nat_of_N
    (BinNat.N.pos
      (BinNums.xI (BinNums.xI (BinNums.xI (BinNums.xI BinNums.xH))))).

Definition leanNat32 : Nat :=
  Nat_of_N
    (BinNat.N.pos
      (BinNums.xO
        (BinNums.xO
          (BinNums.xO (BinNums.xO (BinNums.xO BinNums.xH)))))).

Definition leanInt2 : CslibTo1000000.Int :=
  CslibTo1000000.ofNat0 CslibTo1000000.Int leanNat2
    (CslibTo1000000.instOfNat leanNat2).

Definition leanIntPow (exponent : Nat) : CslibTo1000000.Int :=
  CslibTo1000000.hPow0 CslibTo1000000.Int Nat CslibTo1000000.Int
    (CslibTo1000000.instHPow_inst3 CslibTo1000000.Int Nat
      (CslibTo1000000.instPowNat_inst1 CslibTo1000000.Int
        CslibTo1000000.Int_instNatPow))
    leanInt2 exponent.

Definition leanIntMul
    (left right : CslibTo1000000.Int) : CslibTo1000000.Int :=
  CslibTo1000000.hMul0 CslibTo1000000.Int CslibTo1000000.Int
    CslibTo1000000.Int
    (CslibTo1000000.instHMul_inst1 CslibTo1000000.Int
      CslibTo1000000.Int_instMul)
    left right.

Strategy expand
  [leanNat2 leanNat31 leanNat32 leanInt2 leanIntPow leanIntMul].

Fail Definition int_pow_step_reduces_through_classes :
  leanIntPow leanNat32 = leanIntMul leanInt2 (leanIntPow leanNat31) :=
  eq_refl _.

Definition nat_pow_succ_reduces (base exponent : Nat) :
  Nat_pow base (Nat_succ exponent) =
  Nat_mul (Nat_pow base exponent) base :=
  @eq_refl Nat (Nat_pow base (Nat_succ exponent)).

Fail Definition compact_nat_succ_reduces :
  leanNat32 = Nat_succ leanNat31 :=
  @eq_refl Nat leanNat32.

Fail Definition nat_pow_unfolds_one_compact_step :
  Nat_pow leanNat2 leanNat32 =
  Nat_mul (Nat_pow leanNat2 leanNat31) leanNat2 :=
  @eq_refl Nat (Nat_pow leanNat2 leanNat32).

Fail Definition nat_pow_step_reduces_after_commuting_mul :
  Nat_pow leanNat2 leanNat32 =
  Nat_mul leanNat2 (Nat_pow leanNat2 leanNat31) :=
  @eq_refl Nat (Nat_pow leanNat2 leanNat32).

Definition int_pow_step_reduces_directly :
  CslibTo1000000.Int_pow leanInt2 leanNat32 =
  CslibTo1000000.Int_mul leanInt2
    (CslibTo1000000.Int_pow leanInt2 leanNat31) :=
  @eq_refl CslibTo1000000.Int
    (CslibTo1000000.Int_pow leanInt2 leanNat32).
