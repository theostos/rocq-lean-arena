Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

Fixpoint delay (n : nat) : nat :=
  match n with O => O | S p => delay p + delay p end.
Definition delayed_type := match delay 28 with O => nat | S _ => bool end.

Record Box := { value : nat }.
Definition wrap (A : Type) (x : nat) : Box :=
  let y := x in {| value := y |}.

Goal forall x, (wrap delayed_type x).(value) = (wrap bool x).(value).
Proof.
  intro x.
  exact_no_check (eq_refl (wrap delayed_type x).(value)).
Qed.

Goal (wrap nat 0).(value) = (wrap nat 1).(value).
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.
