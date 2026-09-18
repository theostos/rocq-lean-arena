From LeanImport Require Import Lean.
From Stdlib Require Import NArith.BinNat.
Require Import Adjacent.
Set Kernel Conversion Dep Heuristic.

Definition huge := CompactNat 18446744073709551616%N.
Definition previous := CompactNat 18446744073709551615%N.
Goal eq (Adjacent.Nat_ble huge huge) Bool_true.
Proof. exact_no_check (eq_refl Bool_true). Timeout 5 Qed.
Goal eq (Adjacent.Nat_ble huge previous) Bool_false.
Proof. exact_no_check (eq_refl Bool_false). Timeout 5 Qed.
Goal eq (Adjacent.Nat_ble previous huge) Bool_true.
Proof. exact_no_check (eq_refl Bool_true). Timeout 5 Qed.
Goal eq (Adjacent.Nat_blt huge huge) Bool_false.
Proof. exact_no_check (eq_refl Bool_false). Timeout 5 Qed.
Goal eq (Adjacent.Nat_blt previous huge) Bool_true.
Proof. exact_no_check (eq_refl Bool_true). Timeout 5 Qed.
Goal eq (Adjacent.Nat_ble huge previous) Bool_true.
Proof. exact_no_check (eq_refl Bool_true). Fail Qed. Abort.

(* The wrapper uses the imported comparison also at open arguments. *)
Definition source_strict_wrapper (n m : Nat) :
  eq (Adjacent.Nat_blt n m) (Adjacent.Nat_ble (Nat_succ n) m) :=
  eq_refl _.

Definition wrong_le (n m : Nat) := Bool_true.
Fail Register wrong_le as kernel.peano_nat_ble.
