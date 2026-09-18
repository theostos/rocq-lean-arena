Set Kernel Conversion Dep Heuristic.

Symbol pick : nat -> nat.
Rewrite Rule pick_rew := pick ?x => ?x.
Symbol through : (nat -> nat) -> nat -> nat.
Rewrite Rule through_rew := through (fun n => S ?body) => fun n => S ?body.

Goal forall x, pick x = x.
Proof. intro x. exact_no_check (eq_refl x). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun _ : nat => x).
Proof. intro x. exact_no_check (eq_refl (fun _ : nat => x)). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun y : nat => y).
Proof. intro x. exact_no_check (eq_refl (fun y : nat => y)). Fail Qed. Abort.

Goal forall x, through (fun n => S (x + n)) = (fun n => S (x + n)).
Proof. intro x. exact_no_check (eq_refl (fun n => S (x + n))). Timeout 5 Qed.
Goal forall x, (fun y => through (fun n => S (x + n)) y) = (fun y => S (x + y)).
Proof. intro x. exact_no_check (eq_refl (fun y => S (x + y))). Timeout 5 Qed.
Goal forall x, through (fun _ : nat => S x) = (fun n : nat => S n).
Proof. intro x. exact_no_check (eq_refl (fun n : nat => S n)). Fail Qed. Abort.
