(* Rewrite-rule holes use HigherOrder substitutions even at arity zero.
   Those entries must take the ordinary conversion path, without applying
   the relocation rules for Regular substitutions. *)
Set Kernel Conversion Dep Heuristic.

Symbol pick : nat -> nat.
Rewrite Rule pick_rew := pick ?x => ?x.

Goal forall x, pick x = x.
Proof. intro x. exact_no_check (eq_refl x). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun _ : nat => x).
Proof. intro x. exact_no_check (eq_refl (fun _ : nat => x)). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun y : nat => y).
Proof. intro x. exact_no_check (eq_refl (fun y : nat => y)). Fail Qed. Abort.

Goal forall x, (fun y z : nat => pick (x + y)) = (fun y z : nat => x + y).
Proof. intro x. exact_no_check (eq_refl (fun y z : nat => x + y)). Timeout 5 Qed.
Goal forall x, (fun y z : nat => pick (x + y)) = (fun y z : nat => x + z).
Proof. intro x. exact_no_check (eq_refl (fun y z : nat => x + z)). Fail Qed. Abort.
Goal forall x, (fun y : nat => let captured := x in pick captured) = (fun _ : nat => x).
Proof. intro x. exact_no_check (eq_refl (fun _ : nat => x)). Timeout 5 Qed.
