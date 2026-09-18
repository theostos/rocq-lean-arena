From LeanImport Require Import Lean.
Require Import Prefix.
Set Kernel Conversion Dep Heuristic.
Section Access.
Context (n : Nat).
Let A := Std_Sat_Literal_inst1 (Std_Tactic_BVDecide_LRAT_Internal_PosFin n).
Context (xs : List_inst1 A) (j : Fin (List_length_inst1 A xs)).
Let item := List_get_inst1 A xs j.
Goal Lean.eq item (Prod_mk_inst3 _ _ (fst3 _ _ item) (snd3 _ _ item)).
Proof. exact_no_check (Lean.eq_refl item). Timeout 5 Qed.

Let array_item := Array_getInternal_inst1 A (Array_mk_inst1 A xs)
  (Fin_val _ j) (Lean.isLt _ j).
Goal Lean.eq array_item item.
Proof. exact_no_check (Lean.eq_refl item). Timeout 5 Qed.
Goal Lean.eq array_item (Prod_mk_inst3 _ _ (fst3 _ _ item) (snd3 _ _ item)).
Proof. exact_no_check (Lean.eq_refl item). Timeout 5 Qed.
Let first := fst3 _ _ item.
Goal Lean.eq array_item (Prod_mk_inst3 _ _
  (Subtype_mk Nat _ (Prefix.val _ _ first) (Prefix.property _ _ first))
  (snd3 _ _ item)).
Proof. exact_no_check (Lean.eq_refl array_item). Timeout 5 Qed.
End Access.
