Set Kernel Conversion Dep Heuristic.

Symbol pick : nat -> nat.
Rewrite Rule pick_rew := pick ?x => ?x.
Symbol through : forall A : Type, A -> A.
Rewrite Rule through_rew := through (forall x : ?A, ?B) ?f => fun x => ?f x.

Goal forall x, pick x = x.
Proof. intro x. exact_no_check (eq_refl x). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun _ : nat => x).
Proof. intro x. exact_no_check (eq_refl (fun _ : nat => x)). Timeout 5 Qed.
Goal forall x, (fun y : nat => pick x) = (fun y : nat => y).
Proof. intro x. exact_no_check (eq_refl (fun y : nat => y)). Fail Qed. Abort.

Goal forall x, through _ (fun n => (x + n, n)) = (fun n => (x + n, n)).
Proof. intro x. exact_no_check (eq_refl (fun n => (x + n, n))). Timeout 5 Qed.
Goal forall x, (fun y => through _ (fun n => (x + n, n)) y) = (fun y => (x + y, y)).
Proof. intro x. exact_no_check (eq_refl (fun y => (x + y, y))). Timeout 5 Qed.
Goal forall x, through _ (fun n : nat => (x, n)) = (fun n : nat => (n, n)).
Proof. intro x. exact_no_check (eq_refl (fun n : nat => (n, n))). Fail Qed. Abort.
