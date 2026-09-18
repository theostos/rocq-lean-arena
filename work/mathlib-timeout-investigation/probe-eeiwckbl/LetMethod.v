Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

Fixpoint delay (n : nat) : nat :=
  match n with O => O | S p => delay p + delay p end.
Definition delayed_type := match delay 28 with O => nat | S _ => bool end.

Record Method := { run : nat -> nat }.
Definition method (A : Type) (f : nat -> nat) : Method :=
  let g := f in {| run := g |}.

Goal forall f, (method delayed_type f).(run) = (method bool f).(run).
Proof. intro f; exact_no_check (eq_refl (method delayed_type f).(run)). Qed.

Record Data := { value : nat }.
Definition data (n : nat) : Data :=
  let computed := delay 28 + n in {| value := computed |}.

Goal forall n, (data (id n)).(value) = (data n).(value).
Proof. intro n; exact_no_check (eq_refl (data n).(value)). Qed.

Goal (method nat (fun _ => 0)).(run) = (method nat (fun _ => 1)).(run).
Proof. exact_no_check (eq_refl (fun _ : nat => 0)). Fail Qed. Abort.
