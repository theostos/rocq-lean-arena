Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

Fixpoint delay (n : nat) : nat :=
  match n with O => O | S p => delay p + delay p end.
Definition delayed_type := match delay 28 with O => nat | S _ => bool end.

Record FunctionBox := { function_of : nat -> nat }.
Definition get (r : FunctionBox) := r.(function_of).
Definition forward (A : Type) (r : FunctionBox) : FunctionBox :=
  {| function_of := fun x => get r x |}.

Time Goal forall r, (forward delayed_type r).(function_of) =
                   (forward bool r).(function_of).
Proof.
  Time intro r.
  Time exact_no_check (eq_refl (forward delayed_type r).(function_of)).
Time Qed.

Record Getter := { coerce : FunctionBox -> nat -> nat }.
Definition forward_partial (A : Type) : Getter := {| coerce := get |}.
Goal (forward_partial delayed_type).(coerce) = (forward_partial bool).(coerce).
Proof.
  exact_no_check (eq_refl (forward_partial delayed_type).(coerce)).
Qed.

Goal forall r, (forward nat r).(function_of) = (fun _ => O).
Proof.
  intro r.
  exact_no_check (eq_refl (forward nat r).(function_of)).
Fail Qed.
Abort.

Definition compose (f g : nat -> nat) x := f (g x).
Definition composed (A : Type) (f g : nat -> nat) : FunctionBox :=
  {| function_of := compose f g |}.

Goal forall f g, (composed delayed_type f g).(function_of) =
                 (composed bool f g).(function_of).
Proof.
  intros f g.
  exact_no_check (eq_refl (composed delayed_type f g).(function_of)).
Qed.
