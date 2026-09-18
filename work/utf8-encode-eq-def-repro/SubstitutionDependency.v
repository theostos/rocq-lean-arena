Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Record Box := box { value : nat }.
Fixpoint duplicate (n : nat) : nat :=
  match n with
  | O => O
  | S n => Nat.add (duplicate n) (duplicate n)
  end.
Definition expensive (n : nat) := duplicate 32.
Definition projected (f : nat -> nat) (n : nat) := box (f n).
Definition nested (f : nat -> nat -> nat) (n : nat) :=
  projected (fun x => f n x) n.
Strategy -10 [expensive].
Strategy 10 [projected nested].

(* The dependency comes from the substituted function, rather than the
   global body of [projected]. The argument remains open. *)
Definition substituted_dependency (n : nat) :
  expensive n = value (projected (fun x => expensive x) n).
Proof. exact_no_check (eq_refl (expensive n)). Timeout 5 Qed.
Definition substituted_dependency_reverse (n : nat) :
  value (projected (fun x => expensive x) n) = expensive n.
Proof. exact_no_check (eq_refl (expensive n)). Timeout 5 Qed.

(* Resolve the saved substitution outside both lambda binders. *)
Definition nested_dependency (n : nat) :
  expensive n = value (nested (fun x y => expensive x) n).
Proof. exact_no_check (eq_refl (expensive n)). Timeout 5 Qed.
Definition nested_dependency_reverse (n : nat) :
  value (nested (fun x y => expensive x) n) = expensive n.
Proof. exact_no_check (eq_refl (expensive n)). Timeout 5 Qed.

(* Shared let substitutions and a dependent lambda domain. *)
Definition shared_dependency (n : nat) :
  expensive n =
    (let f := fun x => expensive x in value (nested (fun x y => f x) n)).
Proof. exact_no_check (eq_refl (expensive n)). Timeout 5 Qed.
Definition dependent_projected (f : forall x : nat, x = x -> nat) (n : nat) :=
  box (f n (eq_refl n)).
Definition dependent_domain (n : nat) :
  expensive n = value (dependent_projected (fun x (_ : x = x) => expensive x) n).
Proof. exact_no_check (eq_refl (expensive n)). Timeout 5 Qed.

(* An unfolding preference must not accept a changed result or an opaque
   body. Keep these controls small enough to report a real rejection. *)
Definition unequal_substitution (n : nat) :
  n = value (projected (fun x => S x) n).
Proof. exact_no_check (eq_refl n). Timeout 5 Fail Qed. Abort.
Definition unequal_nested (n : nat) :
  value (nested (fun x y => S y) n) = n.
Proof. exact_no_check (eq_refl n). Timeout 5 Fail Qed. Abort.
Definition hidden (n : nat) : nat.
Proof. exact n. Qed.
Definition opaque_substitution (n : nat) :
  n = value (projected hidden n).
Proof. exact_no_check (eq_refl n). Timeout 5 Fail Qed. Abort.
