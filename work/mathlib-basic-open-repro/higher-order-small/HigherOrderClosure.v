Set Kernel Conversion Dep Heuristic.

Symbol pick : nat -> nat.
Rewrite Rule pick_rew := pick ?x => ?x.
Symbol through : (nat -> nat) -> nat -> nat.
Rewrite Rule through_rew := through (fun n => ?body) => fun n => ?body.

Goal forall x, pick x = x.
Proof. intro x. exact_no_check (eq_refl x). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun _ : nat => x).
Proof. intro x. exact_no_check (eq_refl (fun _ : nat => x)). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun y : nat => y).
Proof. intro x. exact_no_check (eq_refl (fun y : nat => y)). Fail Qed. Abort.

Goal forall x, through (fun n => x + n) = (fun n => x + n).
Proof. intro x. exact_no_check (eq_refl (fun n => x + n)). Timeout 5 Qed.
Goal forall x, (fun y => through (fun n => x + n) y) = (fun y => x + y).
Proof. intro x. exact_no_check (eq_refl (fun y => x + y)). Timeout 5 Qed.
Goal forall x, through (fun _ : nat => x) = (fun n : nat => n).
Proof. intro x. exact_no_check (eq_refl (fun n : nat => n)). Fail Qed. Abort.
