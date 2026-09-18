Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Inductive Truth : SProp := truth.

Fixpoint delay (n : nat) : nat :=
  match n with
  | O => O
  | S p => delay p + delay p
  end.

Definition delayed_type : Type :=
  match delay 28 with O => nat | S _ => bool end.

Record Relation (A : Type) := { holds : list A -> SProp }.
Definition indiscrete (A : Type) : Relation A :=
  {| holds := fun _ => Truth |}.

Goal @holds delayed_type (indiscrete delayed_type) (@nil delayed_type) ->
     @holds bool (indiscrete bool) (@nil bool).
Proof. intro h; exact_no_check h. Qed.
