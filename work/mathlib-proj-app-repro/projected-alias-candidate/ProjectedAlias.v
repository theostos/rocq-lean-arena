Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Inductive Tree := leaf | node : (nat -> Tree) -> (nat -> Tree) -> Tree.
Fixpoint left (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => left k) (fun _ => left k) end.
Fixpoint right (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => right k) (fun _ => right k) end.
Record Inner := inner { method : nat -> nat }.
Definition innerWrap (_ : Tree) := inner (fun x => x).
Record Outer := outer { wrapped : Inner }.
Definition outerWrap (t : Tree) := outer (innerWrap t).
Goal (outerWrap (left 24)).(wrapped).(method) =
     (outerWrap (right 24)).(wrapped).(method).
Proof. exact_no_check (eq_refl ((outerWrap (left 24)).(wrapped).(method))).
Timeout 5 Qed.
