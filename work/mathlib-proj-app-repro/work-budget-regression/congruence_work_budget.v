Set Kernel Conversion Dep Heuristic.

Inductive Tree := leaf : Tree | node : (nat -> Tree) -> (nat -> Tree) -> Tree.
Fixpoint left (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => left k) (fun _ => left k) end.
Fixpoint right (n : nat) : Tree :=
  match n with O => leaf | S k => node (fun _ => right k) (fun _ => right k) end.
Definition discard (_ : Tree) := O.

(* The old depth-only limit permits exponentially wide speculation. Neither
   application actually needs its tree. Separate lambda binders also exercise
   the success cache's context checks. Check in the kernel at Qed. *)
Goal discard (left 24) = discard (right 24).
Proof. exact_no_check (eq_refl (discard (left 24))). Timeout 5 Qed.
Goal discard (right 24) = discard (left 24).
Proof. exact_no_check (eq_refl (discard (left 24))). Timeout 5 Qed.
Goal forall x : nat, (fun _ => discard (left 24)) x = discard (right 24).
Proof. intro x. exact_no_check (eq_refl (discard (left 24))). Timeout 5 Qed.

(* Abandoning speculation must still check the unfolded results. Put the
   expensive tree last so right-to-left congruence reaches it first. *)
Definition choose (b : bool) (_ : Tree) := if b then O else S O.
Goal choose true (left 24) = choose false (right 24).
Proof. exact_no_check (eq_refl (choose true (left 24))). Timeout 5 Fail Qed. Abort.
Goal choose false (right 24) = choose true (left 24).
Proof. exact_no_check (eq_refl (choose true (left 24))). Timeout 5 Fail Qed. Abort.

(* Local and opaque heads cannot unfold: their mandatory comparisons must
   be allowed more work than the optional probe budget. *)
Definition sealed (t : Tree) : Tree.
Proof. exact t. Qed.
Goal sealed (left 12) = sealed (right 12).
Proof. exact_no_check (eq_refl (sealed (left 12))). Timeout 5 Qed.
Goal forall f : Tree -> Tree, f (left 12) = f (right 12).
Proof. intro f. exact_no_check (eq_refl (f (left 12))). Timeout 5 Qed.

(* Exhaustion is caught by the outer probe owner, not a nested comparison. *)
Definition keep (t : Tree) := t.
Goal discard (keep (left 24)) = discard (keep (right 24)).
Proof. exact_no_check (eq_refl (discard (keep (left 24)))). Timeout 5 Qed.
Goal keep (left 12) = keep (right 12).
Proof. exact_no_check (eq_refl (keep (left 12))). Timeout 5 Qed.
