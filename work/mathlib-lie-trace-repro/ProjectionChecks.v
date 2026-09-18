Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record Ops := ops { method : nat -> nat; noise : nat }.
Fixpoint slow (n : nat) : nat :=
  match n with O => O | S k => match slow k with O => slow k | S _ => O end end.
Definition wrapper n := ops (fun x => x) n.
Definition alias n := wrapper n.
Goal forall n x, method (alias n) x = method (wrapper n) x.
Proof. intros. exact_no_check (eq_refl (method (alias n) x)). Timeout 5 Qed.
(* Comparing all source fields would evaluate the expensive noise, even
   though projecting [method] discards it. *)
Goal method (alias (slow 26)) 7 = method (wrapper 0) 7.
Proof. exact_no_check (eq_refl 7). Timeout 5 Qed.
Goal method (wrapper 0) 7 = method (alias (slow 26)) 7.
Proof. exact_no_check (eq_refl 7). Timeout 5 Qed.
Goal forall n m x y, method (wrapper n) x = method (wrapper m) y.
Proof. intros. exact_no_check (eq_refl x). Fail Qed. Abort.
Goal noise (wrapper 0) = noise (wrapper 1).
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.
Record Box := box { inner : Ops }.
Definition nested n := box (alias n).
Goal forall n x, method (inner (nested n)) x = method (wrapper n) x.
Proof. intros. exact_no_check (eq_refl x). Timeout 5 Qed.
