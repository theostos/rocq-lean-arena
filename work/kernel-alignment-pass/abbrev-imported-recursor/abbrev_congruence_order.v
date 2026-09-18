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
(* The importer also marks its generated recursor definitions Expand
   (declare_ind in lean.ml). Stdlib's nat_rect otherwise remains a regular
   definition, unlike the primitive recursor under Lean's recOn wrapper. *)
Strategy expand [nat_rect].

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

(* Ordinary congruence remains available when the definition is opaque. *)
Opaque abbrev_rec.
Definition zero_alias := 0.
Goal abbrev_rec zero_alias 7 (fun _ _ => 0) =
     abbrev_rec 0 7 (fun _ _ => 0).
Proof.
  exact_no_check (eq_refl (abbrev_rec 0 7 (fun _ _ => 0))).
  Timeout 5 Qed.
