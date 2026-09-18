(* Kernel checks for structural comparison through suspended substitutions.
   Negative tests must still reject changed data, scope and universes. *)
Set Kernel Conversion Dep Heuristic.
Set Primitive Projections.

Record Box (A : Type) := box { value : A }.
Arguments box {A} _.
Arguments value {A} _.

Definition via_let {A B : Type} (f : A -> B) :=
  let h := f in fun x => h x.
Definition via_beta {A B : Type} (f : A -> B) :=
  fun x => (fun g => g x) f.

Goal forall (A B : Type) (f : A -> B), via_let f = via_beta f.
Proof. intros. exact_no_check (eq_refl (via_let f)). Timeout 5 Qed.
Goal forall (A B : Type) (f : A -> B), via_beta f = via_let f.
Proof. intros. exact_no_check (eq_refl (via_let f)). Timeout 5 Qed.
Goal forall (f : nat -> nat), (fun x => via_let f x) = f.
Proof. intros. exact_no_check (eq_refl f). Timeout 5 Qed.
Goal forall (A : Type) (x : A),
  (fun y => value (box y)) x = (fun y => y) x.
Proof. intros. exact_no_check (eq_refl x). Timeout 5 Qed.

Goal forall (A : Type) (outer : A),
  (fun inner : A => via_let (fun _ : A => outer) inner) =
  (fun inner : A => outer).
Proof. intros. exact_no_check (eq_refl (fun _ : A => outer)). Timeout 5 Qed.
Goal forall (A : Type) (outer : A),
  (fun inner : A => via_let (fun _ : A => outer) inner) =
  (fun inner : A => inner).
Proof. intros. exact_no_check (eq_refl (fun inner : A => inner)). Fail Qed. Abort.
Goal forall (f : nat -> nat),
  (fun x y => via_let f x) = (fun x y : nat => via_beta f y).
Proof. intros. exact_no_check (eq_refl (fun x y : nat => via_let f x)). Fail Qed. Abort.

Inductive Evidence : SProp := evidence.
Goal (fun (_ : Evidence) x => via_let S x) =
     (fun (_ : Evidence) x => via_beta S x).
Proof. exact_no_check (eq_refl (fun (_ : Evidence) x => via_let S x)). Timeout 5 Qed.
Goal (fun (_ : Evidence) x => via_let S x) =
     (fun (_ : Evidence) x => x).
Proof. exact_no_check (eq_refl (fun (_ : Evidence) x => x)). Fail Qed. Abort.

Definition sealed (n : nat) : nat.
Proof. exact n. Qed.
Goal sealed 0 = 0.
Proof. exact_no_check (eq_refl 0). Fail Qed. Abort.
Goal box 0 = box 1.
Proof. exact_no_check (eq_refl (box 0)). Fail Qed. Abort.

Universe low high.
Constraint low < high.
Goal Type@{low} = Type@{high}.
Proof. exact_no_check (eq_refl Type@{low}). Fail Qed. Abort.
