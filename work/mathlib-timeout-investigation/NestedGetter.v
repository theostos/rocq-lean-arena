Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

Fixpoint delay (n : nat) : nat :=
  match n with O => O | S p => delay p + delay p end.
Definition delayed_type := match delay 28 with O => nat | S _ => bool end.

Record Inner := { run : nat -> nat }.
Record Outer := { inner : Inner }.
Definition wrap (A : Type) (f : nat -> nat) : Outer :=
  {| inner := {| run := f |} |}.

Goal forall f, (wrap delayed_type f).(inner).(run) = (wrap bool f).(inner).(run).
Proof.
  intro f.
  exact_no_check (eq_refl (wrap delayed_type f).(inner).(run)).
Qed.

Goal (wrap nat (fun _ => 0)).(inner).(run) = (wrap nat (fun _ => 1)).(inner).(run).
Proof. exact_no_check (eq_refl (fun _ : nat => 0)). Fail Qed. Abort.
