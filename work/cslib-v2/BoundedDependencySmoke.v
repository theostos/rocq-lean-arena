From Corelib Require Import Init.Datatypes Init.Logic.

Set Primitive Projections.
Set Kernel Conversion Dep Heuristic.

(* Structural smoke coverage. The discriminating regression is the unchanged
   Lean declaration imported by CslibV2Blocker6231278.v. *)
Inductive Token : SProp := token.
Record Box := { run_box : nat -> nat }.

Fixpoint box_fold {A : Type} (step : A -> nat -> nat)
    (proof : Token) (xs : list A) {struct xs} : Box :=
  match xs with
  | nil => {| run_box := fun acc => acc |}
  | cons x rest =>
      {| run_box := fun acc =>
           run_box (box_fold step proof rest) (step x acc) |}
  end.

Definition cons_alias {A : Type} (x : A) (xs : list A) := cons x xs.

Section Checks.
  Context {A : Type} (step : A -> nat -> nat)
    (p q : Token) (x : A) (xs : list A).

  (* Direct list arguments precede a projection and external accumulator;
     distinct SProp arguments exercise the relevance mask. *)
  Definition fold_cons (acc : nat) :
    run_box (box_fold step p (cons x xs)) acc =
    run_box (box_fold step q xs) (step x acc) := eq_refl _.

  Definition fold_cons_lets :
    let step' := step in
    forall acc : nat,
      let acc' := acc in
      run_box (box_fold step' p (cons x xs)) acc' =
      run_box (box_fold step' q xs) (step' x acc') :=
    fun acc => eq_refl _.

  (* Trailing application arguments must still be checked. *)
  Fail Definition wrong_accumulator (acc : nat) :
    run_box (box_fold step p (cons x xs)) acc =
    run_box (box_fold step q xs) acc := eq_refl _.

  (* A successful prioritized comparison must not hide a different step. *)
  Fail Definition wrong_step (acc : nat) :
    run_box (box_fold step p (cons_alias x nil)) acc =
    run_box (box_fold (fun (_ : A) n => S n) q (cons x nil)) acc :=
    eq_refl _.
End Checks.
