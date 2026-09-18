(* Standalone conversion controls for an operation lifted through two records.
   This models the projection shape of Int8.toBitVec_not, not its timeout. *)
Set Primitive Projections.
Set Universe Polymorphism.

Record Box (A : Type) := Wrap { unbox : A }.
Record Outer (A : Type) := Pack { inner : Box A }.
Record Operation (A : Type) := MakeOperation {
  run : A -> A;
  unused : nat
}.

Arguments Wrap {A} _.
Arguments Pack {A} _.
Arguments MakeOperation {A} _ _.
Arguments unbox {A} _.
Arguments inner {A} _.
Arguments run {A} _ _.

Definition unwrap {A} (s : Outer A) : A := unbox (inner s).
Definition lift_operation {A} (base : Operation A) (s : Outer A) : Outer A :=
  Pack (Wrap (run base (unwrap s))).
Definition outer_operation {A} (base : Operation A) : Operation (Outer A) :=
  MakeOperation (lift_operation base) 0.

(* The selected operation remains neutral: no computation of it is needed. *)
Definition neutral_forward {A} (base : Operation A) (s : Outer A) :
  unwrap (run (outer_operation base) s) = run base (unwrap s) :=
  eq_refl (unwrap (run (outer_operation base) s)).

Definition neutral_backward {A} (base : Operation A) (s : Outer A) :
  run base (unwrap s) = unwrap (run (outer_operation base) s) :=
  eq_refl (run base (unwrap s)).

Definition operation_zero {A} (f : A -> A) : Operation A := MakeOperation f 0.
Definition operation_one {A} (f : A -> A) : Operation A := MakeOperation f 1.

(* Unequal producers can still have the same selected field. *)
Definition selected_field_forward {A} (f : A -> A) (s : Outer A) :
  unwrap (run (outer_operation (operation_zero f)) s) =
  run (operation_one f) (unwrap s) := eq_refl _.

Definition selected_field_backward {A} (f : A -> A) (s : Outer A) :
  run (operation_one f) (unwrap s) =
  unwrap (run (outer_operation (operation_zero f)) s) := eq_refl _.

Fail Definition different_records {A} (f : A -> A) :
  operation_zero f = operation_one f := eq_refl _.

Fail Definition different_selected_fields {A} (f g : A -> A) (s : Outer A) :
  unwrap (run (outer_operation (operation_zero f)) s) =
  run (operation_one g) (unwrap s) := eq_refl _.

Fail Definition different_arguments {A} (base : Operation A) (s t : Outer A) :
  unwrap (run (outer_operation base) s) = run base (unwrap t) := eq_refl _.

(* Qed makes the body genuinely opaque, including to the kernel. *)
Definition sealed_outer_operation {A} (base : Operation A) : Operation (Outer A).
Proof. exact (outer_operation base). Qed.

Fail Definition opaque_producer {A} (base : Operation A) (s : Outer A) :
  unwrap (run (sealed_outer_operation base) s) = run base (unwrap s) :=
  eq_refl _.

(* A bounded transparent computation that the wrapper equalities need not run.
   The small fuel keeps this a control, not a resource stress benchmark. *)
Fixpoint branch_work (fuel x : nat) : nat :=
  match fuel with
  | O => x
  | S k => S (branch_work k (branch_work k x))
  end.

Definition costly_operation : Operation nat := MakeOperation (branch_work 12) 0.

Definition transparent_forward (s : Outer nat) :
  unwrap (run (outer_operation costly_operation) s) =
  run costly_operation (unwrap s) := eq_refl _.

Definition transparent_backward (s : Outer nat) :
  run costly_operation (unwrap s) =
  unwrap (run (outer_operation costly_operation) s) := eq_refl _.
