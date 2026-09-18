From LeanImport Require Import Lean ULiftCumulativeRegistration.

(** Combined test for the [ULift] cumulative translation.

    The dump [dumps/ulift] exports:
    - [Scratch.example1 : MyProd (ULift.{Set+1, Prop} MyNat) Type]
      -- uses [ULift] at instance 2 (s = Prop), always inductive;
    - [Scratch.useUp.{u} (α : Type u) (x : α) : ULift.{u, u} α
         := ULift.up.{u, u} α x]
      -- uses [ULift.up] at instance 0, exercising the cumul path. *)
Redirect "ulift.log" Lean Import "../dumps/ulift".

(** SProp instance falls through to the inductive [ULift_inst2], so the type
    of [example1] is [MyProd (ULift_inst2 MyNat) Type] and therefore *not*
    convertible with the bare [MyProd MyNat Type]. *)
Check Scratch_example1.
Fail Check Scratch_example1 : Scratch_MyProd Scratch_MyNat Type.

(** At instance 0, [ULift_cumul] is a transparent identity, so [α] is
    convertible with [ULift_cumul α]. *)
Check (fun (α : Type) (x : α) => (x : ULift_cumul α)).

(** Regression: before the four-universe rewrite of the cumul signatures
    (and matching [algs] in lean.ml), importing [useUp] crashed with a
    universe mismatch / kernel assertion because the cumul refs were
    instantiated at [{u, u}] instead of [{u, u, u+1, u+1}]. *)
Set Printing Universes.
Check Scratch_useUp.
Print Scratch_useUp.

(** Applying [useUp] to a concrete type and term must succeed. *)
Check Scratch_useUp Nat Nat_zero.

(** Pointwise reduction: [ULift_up_cumul] is the identity so
    [Scratch_useUp α x] is convertible with [x]. *)
Goal forall (α : Type) (x : α), Scratch_useUp α x = x.
Proof. reflexivity. Qed.
