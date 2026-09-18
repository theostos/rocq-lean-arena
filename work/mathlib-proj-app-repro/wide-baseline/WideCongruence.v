Set Kernel Conversion Dep Heuristic.

Inductive Tree := leaf : Tree | node : (nat -> Tree) -> (nat -> Tree) -> Tree.
Fixpoint left (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => left k) (fun _ => left k) end.
Fixpoint right (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => right k) (fun _ => right k) end.
Definition discard (_ : Tree) := O.

(* Congruence explores a wide tree, although evaluating discard needs none
   of it. Crossing separate lambda binders also tests the cache's scope. *)
Goal discard (left 24) = discard (right 24).
Proof. exact_no_check (eq_refl (discard (left 24))). Timeout 5 Qed.
