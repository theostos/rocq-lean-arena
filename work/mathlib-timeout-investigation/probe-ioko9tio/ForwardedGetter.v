Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

Fixpoint delay (n : nat) : nat :=
  match n with O => O | S p => delay p + delay p end.
Definition delayed_type := match delay 28 with O => nat | S _ => bool end.

Record FunctionBox := { function_of : nat -> nat }.
Definition get (r : FunctionBox) := r.(function_of).
Definition forward (A : Type) (r : FunctionBox) : FunctionBox :=
  {| function_of := fun x => get r x |}.

Goal forall r, get (forward delayed_type r) = get (forward bool r).
  intro r.
  exact_no_check (eq_refl (get (forward delayed_type r))).
Qed.

Goal forall r, get (forward nat r) = (fun _ => O).
  intro r.
  exact_no_check (eq_refl (get (forward nat r))).
Fail Qed.
Abort.
