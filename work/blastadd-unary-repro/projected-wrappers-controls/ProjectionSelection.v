Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Record Fields := fields { selected : nat; ignored : nat }.
Definition produce (x y : nat) := fields x y.

Definition selected_only (x : nat) :
  selected (produce x 0) = selected (produce x 1) := eq_refl.

Definition selected_under_binder :
  (fun x => selected (produce x 0)) =
  (fun x => selected (produce x 1)) := eq_refl.

(* Conversion checks the last pair component first. Equality of selected
   fields must not be cached as equality of their record sources. *)
Fail Definition distinct_other_field (x : nat) :
  (ignored (produce x 0), selected (produce x 0)) =
  (ignored (produce x 1), selected (produce x 1)) := eq_refl.

Record Functions := functions { run : nat -> nat; tag : nat }.
Definition producer (tag : nat) := functions (fun x => x) tag.

Definition applied_projection (x : nat) :
  run (producer 0) x = run (producer 1) x := eq_refl.

Opaque produce.
Definition opaque_same_source (x y : nat) :
  selected (produce x y) = selected (produce x y) := eq_refl.
Fail Definition opaque_distinct_sources (x : nat) :
  selected (produce x 0) = selected (produce x 1) := eq_refl.
