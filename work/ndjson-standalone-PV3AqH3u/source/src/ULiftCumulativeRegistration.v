(** Cumulative ULift definitions for instance 0 (both r, s non-SProp).

    When this module is [Require Import]ed before [Lean Import], Lean's [ULift]
    (at instance 0) is translated as a transparent definition leveraging
    cumulativity, rather than as an inductive type.  SProp instances (1-3)
    still fall through to normal inductive translation since Rocq does not
    have cumulativity between SProp and Set.

    The signatures carry four universes [r s s1 rs1] with the constraints
    [s < s1], [r < rs1], [s1 <= rs1].  The extra [s1] and [rs1] stand for
    Lean's [s+1] and [max(r+1, s+1)] respectively -- i.e. the actual Rocq
    sort levels at which Lean's [α : Type s] and [ULift.{r,s} α : Type (max r s)]
    live.  The plugin supplies them as algebraic [algs] on every use, matching
    the four-universe shape of the inductive translation of [ULift]. *)

Set Universe Polymorphism.

Definition ULift_cumul@{r s s1 rs1 | s < s1, r < rs1, s1 <= rs1}
  (α : Type@{s1}) : Type@{rs1} := α.
Register ULift_cumul as lean.ULift.cumul.

Definition ULift_up_cumul@{r s s1 rs1 | s < s1, r < rs1, s1 <= rs1}
  {α : Type@{s1}} (a : α) : ULift_cumul@{r s s1 rs1} α := a.
Register ULift_up_cumul as lean.ULift_up.cumul.

Definition ULift_down_cumul@{r s s1 rs1 | s < s1, r < rs1, s1 <= rs1}
  {α : Type@{s1}} (a : ULift_cumul@{r s s1 rs1} α) : α := a.
Register ULift_down_cumul as lean.ULift_down.cumul.

Definition ULift_rec_cumul@{motive r s s1 rs1 | s < s1, r < rs1, s1 <= rs1}
  {α : Type@{s1}} {P : ULift_cumul@{r s s1 rs1} α -> Type@{motive}}
  (mk : forall (down : α), P (ULift_up_cumul@{r s s1 rs1} down))
  (t : ULift_cumul@{r s s1 rs1} α) : P t
  := mk t.
Register ULift_rec_cumul as lean.ULift_rec.cumul.

Definition ULift_ind_cumul@{r s s1 rs1 | s < s1, r < rs1, s1 <= rs1}
  {α : Type@{s1}} {P : ULift_cumul@{r s s1 rs1} α -> SProp}
  (mk : forall (down : α), P (ULift_up_cumul@{r s s1 rs1} down))
  (t : ULift_cumul@{r s s1 rs1} α) : P t
  := mk t.
Register ULift_ind_cumul as lean.ULift_rec.cumul.ind.
