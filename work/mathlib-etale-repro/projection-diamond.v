Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Record Parent := parent { operation : nat -> nat; unused : nat }.
Record Child := child { inherited : Parent; unused_child : nat }.
Fixpoint duplicate (n : nat) : nat :=
  match n with O => O | S k => Nat.add (duplicate k) (duplicate k) end.
Definition delayed_junk (_ : nat) := duplicate 30.
Definition left_parent (n : nat) := parent (fun x => x) (delayed_junk n).
Definition right_parent (n : nat) := parent (fun x => x) (S (delayed_junk n)).
Definition left_child (n : nat) := child (left_parent n) (delayed_junk n).
Definition right_child (n : nat) := child (right_parent n) (S (delayed_junk n)).

(* Comparing complete sources would force an unrelated exponential field.
   Projecting the selected field establishes equality without that work. *)
Goal forall n x, operation (inherited (left_child n)) x =
                 operation (inherited (right_child n)) x.
Proof. intros; exact_no_check (eq_refl x). Timeout 5 Qed.
Goal forall n x, operation (inherited (right_child n)) x =
                 operation (inherited (left_child n)) x.
Proof. intros; exact_no_check (eq_refl x). Timeout 5 Qed.
Goal forall n, (fun x => operation (inherited (left_child n)) x) =
               (fun x => operation (inherited (right_child n)) x).
Proof. intro; exact_no_check (eq_refl (fun x : nat => x)). Timeout 5 Qed.

Definition different n := child (parent S (delayed_junk n)) 0.
Goal operation (inherited (left_child 0)) 0 = operation (inherited (different 0)) 0.
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.
Definition opaque_parent : Parent. Proof. exact (parent (fun x => x) 0). Qed.
Goal operation opaque_parent 0 = 0.
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.
