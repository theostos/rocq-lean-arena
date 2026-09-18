Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.
Record major_source := { major_bool : bool }.
Unset Primitive Projections.
Definition selected_major := {| major_bool := true |}.
Definition ordinary_case (yes no : nat) (b : bool) :=
  match b with true => yes | false => no end.
Opaque selected_major.
Goal ordinary_case 7 8 (major_bool selected_major) = 7.
Proof. exact_no_check (eq_refl 7). Qed.
