From LeanImport Require Import Lean.
From Stdlib Require Import NArith.BinNat.
Require Import Prefix.
Set Kernel Conversion Dep Heuristic.

Definition large := Nat_add (CompactNat 4294967296%N) (CompactNat 1%N).
Definition three := CompactNat 3%N.
Definition quotient := CompactNat 1431655765%N.
Definition two := CompactNat 2%N.

(* These checks go through the conversion machine at Qed, not just the
   elaborator. Division's fuel is the successor of a computed dividend. *)
Goal eq (Nat_div large three) quotient.
Proof. exact_no_check (eq_refl quotient). Timeout 5 Qed.
Goal eq quotient (Nat_div large three).
Proof. exact_no_check (eq_refl quotient). Timeout 5 Qed.
Goal eq (Nat_mod large three) two.
Proof. exact_no_check (eq_refl two). Timeout 5 Qed.
Goal eq two (Nat_mod large three).
Proof. exact_no_check (eq_refl two). Timeout 5 Qed.
Goal eq (Nat_div large Nat_zero) Nat_zero.
Proof. exact_no_check (eq_refl Nat_zero). Timeout 5 Qed.
Goal eq (Nat_mod large Nat_zero) large.
Proof. exact_no_check (eq_refl large). Timeout 5 Qed.

(* A bad quotient/remainder must still be rejected by the kernel. *)
Goal eq (Nat_div large three) (Nat_succ quotient).
Proof. exact_no_check (eq_refl (Nat_succ quotient)). Fail Qed. Abort.
Goal eq (Nat_mod large three) Nat_zero.
Proof. exact_no_check (eq_refl Nat_zero). Fail Qed. Abort.
Goal eq (Nat_div large Nat_zero) large.
Proof. exact_no_check (eq_refl large). Fail Qed. Abort.
