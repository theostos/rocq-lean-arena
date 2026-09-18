(* Instance aliases must not force irrelevant source parameters before selecting
   an applied method. Keep bare fields, opaque definitions and relevant method
   arguments subject to ordinary conversion. *)
Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record Ops := ops { run : nat -> nat }.
Definition infer {A : Type} (a : A) := a.
Definition instance (_ : nat) := ops (fun n => n).
Definition alias (n : nat) := infer (instance n).
Fixpoint duplicate (fuel : nat) : nat :=
  match fuel with O => O | S k => Nat.add (duplicate k) (duplicate k) end.

Goal run (alias (duplicate 32)) 7 = run (alias 0) 7.
Proof. exact_no_check (eq_refl (run (alias 0) 7)). Timeout 5 Qed.
Goal run (alias 0) 7 = run (alias (duplicate 32)) 7.
Proof. exact_no_check (eq_refl (run (alias 0) 7)). Timeout 5 Qed.
Goal run (alias 0) 0 = run (alias 0) 1.
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.

Definition captures (n : nat) := infer (ops (fun _ => n)).
Goal run (captures 0) 7 = run (captures 1) 7.
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.
Definition sealed (n : nat) : Ops.
Proof. exact (alias n). Qed.
Goal run (sealed 0) 7 = 7.
Proof. exact_no_check (eq_refl 7). Fail Qed. Abort.

(* With no record-source parameters, preserve common-method congruence. *)
Definition slow := ops duplicate.
Definition identity (n : nat) := n.
Goal run slow 32 = run slow (identity 32).
Proof. exact_no_check (eq_refl (run slow 32)). Timeout 5 Qed.
