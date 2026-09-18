Set Kernel Conversion Dep Heuristic.

Fixpoint delay (n : nat) : nat :=
  match n with
  | O => O
  | S p => delay p + delay p
  end.

Inductive Indexed (A : Type) (n : nat) : Type := indexed.

Goal Indexed nat (delay 28) -> Indexed bool 0.
Proof.
  intro x.
  exact_no_check x.
Redirect "mismatch.log" Fail Qed.
Abort.

Goal Indexed nat 0 -> Indexed nat 0.
Proof. exact (fun x => x). Qed.
