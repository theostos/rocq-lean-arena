Set Kernel Conversion Dep Heuristic.

Fixpoint costly (n : nat) : nat :=
  match n with
  | O => O
  | S k => match costly k with O => costly k | S _ => O end
  end.
Definition wrapper n := costly n.

(* An ordinary recursive function is not a primitive eliminator. Unfolding
   its alias first exposes the common symbolic call without evaluating it. *)
Goal costly 26 = wrapper 26.
Proof.
  exact_no_check (eq_refl (costly 26)).
  Timeout 5 Qed.
