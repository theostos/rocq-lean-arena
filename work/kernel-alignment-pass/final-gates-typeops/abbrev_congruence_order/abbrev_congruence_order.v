Set Kernel Conversion Dep Heuristic.

Fixpoint expensive (n : nat) : nat :=
  match n with
  | O => O
  | S k => match expensive k with O => expensive k | S _ => O end
  end.

(* Lean's abbreviation hint is mapped to Expand. Its branch arguments are
   not compared before exposing the recursor's actual computation. *)
Definition abbrev_rec (n zero : nat) (step : nat -> nat -> nat) : nat :=
  nat_rect (fun _ => nat) zero step n.
Strategy expand [abbrev_rec].
(* Keep nat_rect at its ordinary priority. It represents the additional
   definition layer around a primitive recursor in the Rocq translation. *)

Goal abbrev_rec 0 7 (fun _ _ => expensive 26) =
     abbrev_rec 0 7 (fun _ _ => expensive 27).
Proof.
  exact_no_check (eq_refl (abbrev_rec 0 7 (fun _ _ => expensive 26))).
  Timeout 5 Qed.

Goal abbrev_rec 0 7 (fun _ _ => expensive 27) =
     abbrev_rec 0 7 (fun _ _ => expensive 26).
Proof.
  exact_no_check (eq_refl (abbrev_rec 0 7 (fun _ _ => expensive 27))).
  Timeout 5 Qed.

(* Reducing an abbreviation must still reject different returned values. *)
Goal abbrev_rec 0 7 (fun _ _ => 0) = abbrev_rec 0 8 (fun _ _ => 0).
Proof. exact_no_check (eq_refl 7). Fail Qed. Abort.

(* An ordinary eliminator, including a parameterized one, has the same
   constructor demand. No Expand hint is supplied for these definitions. *)
Definition ordinary_rec (A : Type) (zero : A) (step : nat -> A -> A) :=
  fix go (n : nat) : A :=
    match n with O => zero | S k => step k (go k) end.

Goal ordinary_rec nat 7 (fun _ _ => expensive 26) 0 =
     ordinary_rec nat 7 (fun _ _ => expensive 27) 0.
Proof.
  exact_no_check (eq_refl (ordinary_rec nat 7 (fun _ _ => expensive 26) 0)).
  Timeout 5 Qed.

(* The visible constructor can have arguments; the selected branch ignores
   the recursive result and hence the expensive zero branch. *)
Goal ordinary_rec nat (expensive 26) (fun _ _ => 7) 1 =
     ordinary_rec nat (expensive 27) (fun _ _ => 7) 1.
Proof.
  exact_no_check (eq_refl (ordinary_rec nat (expensive 26) (fun _ _ => 7) 1)).
  Timeout 5 Qed.

(* A neutral structural argument cannot be assumed to select either branch. *)
Goal forall n, ordinary_rec nat 7 (fun _ _ => 0) n =
               ordinary_rec nat 8 (fun _ _ => 0) n.
Proof. intro n. exact_no_check (eq_refl 7). Fail Qed. Abort.

(* Partial applications still use ordinary congruence/eta, not a guessed
   structural argument position. *)
Definition seven_alias := 7.
Goal ordinary_rec nat seven_alias (fun _ _ => 0) =
     ordinary_rec nat 7 (fun _ _ => 0).
Proof.
  exact_no_check (eq_refl (ordinary_rec nat 7 (fun _ _ => 0))).
  Timeout 5 Qed.

(* Ordinary congruence remains available when the definition is opaque. *)
Opaque abbrev_rec.
Definition zero_alias := 0.
Goal abbrev_rec zero_alias 7 (fun _ _ => 0) =
     abbrev_rec 0 7 (fun _ _ => 0).
Proof.
  exact_no_check (eq_refl (abbrev_rec 0 7 (fun _ _ => 0))).
  Timeout 5 Qed.
