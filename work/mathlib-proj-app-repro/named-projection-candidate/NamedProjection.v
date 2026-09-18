Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Inductive Tree := leaf | node : (nat -> Tree) -> (nat -> Tree) -> Tree.
Fixpoint left (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => left k) (fun _ => left k) end.
Fixpoint right (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => right k) (fun _ => right k) end.
Record Bundle := bundle { method : nat -> nat; unused : Tree }.
Definition select (x : Bundle) := x.(method).
Goal select (bundle (fun x => x) (left 24)) =
     select (bundle (fun x => x) (right 24)).
Proof. exact_no_check (eq_refl (select (bundle (fun x => x) (left 24)))).
Timeout 5 Qed.
