From Stdlib Require PeanoNat ZifyBool Uint63.
From Stdlib Require Export ZArith NArith.
From Stdlib Require Export Lia.
Declare ML Module "coq-lean-import.plugin".

Set Universe Polymorphism.
Set Printing Universes.
Set Primitive Projections.

Declare Scope lean_scope.
Global Open Scope lean_scope.

Global Set Definitional UIP.

Cumulative
Inductive eq@{u|} {α:Type@{u}} (a:α) : α -> SProp
  := eq_refl : eq a a.
Notation "x = y" := (eq x y) : lean_scope.

Register eq as lean.Eq.

Definition eq_mp_sprop@{u|} {α : Type@{u}} {a b : α}
  (P : α -> SProp) (h : @eq α a b) : P a -> P b :=
  match h with eq_refl _ => fun p => p end.

Definition eq_mpr_sprop@{u|} {α : Type@{u}} {a b : α}
  (P : α -> SProp) (h : @eq α a b) : P b -> P a :=
  match h with eq_refl _ => fun p => p end.

Definition lean_eq_of_logic_eq@{u|} {α : Type@{u}} {a b : α}
  (h : Logic.eq a b) : @eq α a b :=
  match h with
  | Logic.eq_refl => eq_refl a
  end.

Inductive eq_inst1@{|} {α:SProp} (a:α) : α -> SProp
  := eq_refl_inst1 : eq_inst1 a a.

Register eq_inst1 as lean.Eq_inst1.

(* Inductive List@{u Lean.u+1.0} (α : Type@{Lean.u+1.0}) : Type@{Lean.u+1.0} :=
    List_nil : List@{u Lean.u+1.0} α
  | List_cons : α -> List@{u Lean.u+1.0} α -> List@{u Lean.u+1.0} α. *)

Monomorphic Universe set.
Inductive List_inst1@{} (α : Type@{set}) : Type@{set} :=
| List_nil_inst1 : List_inst1 α
| List_cons_inst1 : α -> List_inst1 α -> List_inst1 α.

Register List_inst1 as lean.List_inst1.

Module Quot.

  Private Inductive quot@{u|} {α : Type@{u}} (r : α -> α -> SProp) : Type@{u}
    := mk (a:α).

  Register quot as lean.Quot.
  Register mk as lean.Quot.mk.

  Definition lift@{u v|} {α : Type@{u}} {r:α -> α -> SProp} {β : Type@{v}} (f : α -> β)
    : (forall a b : α, r a b -> eq (f a) (f b)) -> quot r -> β
    := fun H q => match q with mk _ x => fun _ => f x end H.

  Register lift as lean.Quot.lift.

  Definition lift_inst2@{u|} {α : Type@{u}} {r:α -> α -> SProp} {β : SProp} (f : α -> β)
    : (forall a b : α, r a b -> eq_inst1 (f a) (f b)) -> quot r -> β
    := fun H q => match q with mk _ x => fun _ => f x end H.

  Register lift_inst2 as lean.Quot.lift_inst2.

  Definition ind@{u|} {α : Type@{u}} {r:α -> α -> SProp} {β : quot r -> SProp}
    : (forall a : α, β (mk r a)) -> forall q : quot r, β q
    := fun f q => match q with mk _ x => f x end.

  Register ind as lean.Quot.ind.

  (* Because quot_inst1 is SProp we don't need to make it Private: the
     axiom declared by lean about it is a tautology. *)
  Inductive quot_inst1@{|} {α : SProp} (r : α -> α -> SProp) : SProp
    := mk_inst1 (a:α).

  Register quot_inst1 as lean.Quot_inst1.
  Register mk_inst1 as lean.Quot.mk_inst1.

  (* This non-uniform translation avoids breaking SR ;) *)
  Definition lift_inst1@{v|} {α : SProp} {r:α -> α -> SProp} {β : Type@{v}} (f : α -> β)
    : (forall a b : α, r a b -> eq (f a) (f b)) -> quot_inst1 r -> β
    := fun _ q => f (match q with mk_inst1 _ x => x end).

  Register lift_inst1 as lean.Quot.lift_inst1.

  Definition lift_inst3@{|} {α : SProp} {r:α -> α -> SProp} {β : SProp} (f : α -> β)
    : (forall a b : α, r a b -> eq_inst1 (f a) (f b)) -> quot_inst1 r -> β
    := fun _ q => f (match q with mk_inst1 _ x => x end).

  Register lift_inst3 as lean.Quot.lift_inst3.

  Definition ind_inst1@{|} {α : SProp} {r:α -> α -> SProp} {β : quot_inst1 r -> SProp}
    : (forall a : α, β (mk_inst1 r a)) -> forall q : quot_inst1 r, β q
    := fun f q => match q with mk_inst1 _ x => f x end.

  Register ind_inst1 as lean.Quot.ind_inst1.

End Quot.

Inductive Nat := Nat_zero : Nat | Nat_succ : Nat -> Nat.

Register Nat as lean.Nat.

Fixpoint double (n : Nat) : Nat :=
  match n with
  | Nat_zero => Nat_zero
  | Nat_succ n => Nat_succ (Nat_succ (double n))
  end.

Register double as lean.Nat_double.

Declare Scope Nat_scope.
Delimit Scope Nat_scope with Nat.
Open Scope Nat_scope.
Bind Scope Nat_scope with Nat.

Inductive Nat_le@{} (n : Nat) : Nat -> SProp :=
| Nat_le_refl : Nat_le n n
| Nat_le_step : forall m : Nat, Nat_le n m -> Nat_le n (Nat_succ m).

Register Nat_le as lean.Nat_le.

Notation "n <= m" := (Nat_le n m) : Nat_scope.
Notation "n < m" := (Nat_le (Nat_succ n) m) (only parsing) : Nat_scope.
(*
Definition Nat_pred (n : Nat) : Nat :=
  match n with
  | Nat_zero => Nat_zero
  | Nat_succ n => n
  end. *)

Variant Or@{} (a a0 : SProp) : SProp :=
| Or_inl : a -> Or a a0
| Or_inr : a0 -> Or a a0.
Register Or as lean.Or.
Record And@{} (a a0 : SProp) : SProp := And_intro
  { left : a;  right : a0 }.
Register And as lean.And.

Inductive sEmpty : SProp := .

Section nat_notation.
  Import ZifyClasses ZArith NArith.
  Fixpoint nat_of_Nat (n : Nat) : nat :=
    match n with
    | Nat_zero => 0
    | Nat_succ n => S (nat_of_Nat n)
    end%nat.
  Fixpoint Nat_of_nat (n : nat) : Nat :=
    match n with
    | O => Nat_zero
    | S n => Nat_succ (Nat_of_nat n)
    end.

  Definition Nat_of_N (n : N) : Nat := Nat_of_nat (N.to_nat n).
  Definition N_of_Nat (n : Nat) : N := N.of_nat (nat_of_Nat n).
  Definition Nat_of_num_uint n : Nat := Nat_of_N (N.of_num_uint n).
  Definition Nat_to_num_uint (n : Nat) := N.to_num_uint (N_of_Nat n).

  Lemma nat2Natid (n : nat) : nat_of_Nat (Nat_of_nat n) = n.
  Proof. induction n as [|n IHn]; cbn; rewrite ?IHn; reflexivity. Qed.
  Lemma Nat2natid (n : Nat) : Nat_of_nat (nat_of_Nat n) = n.
  Proof. induction n as [|n IHn]; cbn; rewrite ?IHn; reflexivity. Qed.

  Lemma rocq_nat_of_Nat_zero :
    Logic.eq (nat_of_Nat Nat_zero) O.
  Proof. reflexivity. Qed.

  Lemma rocq_nat_of_Nat_succ (n : Nat) :
    Logic.eq (nat_of_Nat (Nat_succ n)) (S (nat_of_Nat n)).
  Proof. reflexivity. Qed.

  #[global]
  Monomorphic Instance Inj_Nat_Z : InjTyp Nat Z :=
    mkinj _ _ (fun n => Z.of_nat (nat_of_Nat n)) (fun x =>  0 <= x )%Z (fun n => Nat2Z.is_nonneg _).

  Lemma nat_le_Nat_le' (n m : nat) : (n <= m)%nat -> (Nat_of_nat n <= Nat_of_nat m)%Nat.
  Proof. induction 1; cbn; constructor; assumption. Defined.

  Lemma nat_le_Nat_le (n m : Nat) : (nat_of_Nat n <= nat_of_Nat m)%nat -> (n <= m)%Nat.
  Proof.
    intro H; apply nat_le_Nat_le' in H.
    rewrite !Nat2natid in H; assumption.
  Qed.

  Definition Nat_le_ind (n : Nat) (P : forall m, n <= m -> Prop)
              (H0 : P n (Nat_le_refl n))
              (HS : forall m (H : n <= m), P m H -> P (Nat_succ m) (Nat_le_step n m H))
              m (H : n <= m) : P m H.
  Proof.
    revert m H; fix IH 1; intros [|m] H; [ clear IH | specialize (IH m) ].
    { clear HS.
      revert n P H0 H.
      fix IH 1; intros [|n] P H0 H; [ clear IH | specialize (IH n) ].
      { exact H0. }
      { cut sEmpty; [ destruct 1 | ].
        inversion H. } }
    { specialize (fun H => HS m _ (IH H)).
      clear IH.
      destruct (Nat.eqb (nat_of_Nat n) (nat_of_Nat (Nat_succ m))) eqn:E; [ clear HS | clear H0 ].
      { apply Nat.eqb_eq in E.
        apply (f_equal Nat_of_nat) in E.
        rewrite !Nat2natid in E.
        subst.
        exact H0. }
      { refine (HS _); clear HS.
        inversion H; subst; rewrite ?Nat.eqb_refl in E.
        { congruence. }
        { assumption. } } }
  Qed.

  Register Scheme Nat_le_ind as ind_dep for Nat_le.

  Definition Nat_le_rect (n : Nat) (P : forall m, n <= m -> Type)
              (H0 : P n (Nat_le_refl n))
              (HS : forall m (H : n <= m), P m H -> P (Nat_succ m) (Nat_le_step n m H))
              m (H : n <= m) : P m H.
  Proof.
    revert m H; fix IH 1; intros [|m] H; [ clear IH | specialize (IH m) ].
    { clear HS.
      revert n P H0 H.
      fix IH 1; intros [|n] P H0 H; [ clear IH | specialize (IH n) ].
      { exact H0. }
      { cut sEmpty; [ destruct 1 | ].
        inversion H. } }
    { specialize (fun H => HS m _ (IH H)).
      clear IH.
      destruct (Nat.eqb (nat_of_Nat n) (nat_of_Nat (Nat_succ m))) eqn:E; [ clear HS | clear H0 ].
      { apply Nat.eqb_eq in E.
        apply (f_equal Nat_of_nat) in E.
        rewrite !Nat2natid in E.
        subst.
        exact H0. }
      { refine (HS _); clear HS.
        inversion H; subst; rewrite ?Nat.eqb_refl in E.
        { congruence. }
        { assumption. } } }
  Defined.

  Register Scheme Nat_le_rect as rect_dep for Nat_le.

  Lemma Nat_le_nat_le' (n m : Nat) : (n <= m)%Nat -> (nat_of_Nat n <= nat_of_Nat m)%nat.
  Proof. induction 1; cbn; constructor; assumption. Defined.

  Lemma Nat_le_nat_le (n m : nat) : (Nat_of_nat n <= Nat_of_nat m)%Nat -> (n <= m)%nat.
  Proof.
    intro H; apply Nat_le_nat_le' in H.
    rewrite !nat2Natid in H; assumption.
  Qed.

  Lemma Nat_lt_congr_right_by_nat_of_Nat (n a b : Nat) :
    (n < a)%Nat -> nat_of_Nat a = nat_of_Nat b -> (n < b)%Nat.
  Proof.
    intros H E.
    apply nat_le_Nat_le.
    apply Nat_le_nat_le' in H.
    rewrite <- E; exact H.
  Qed.

  Lemma Nat_le_lt_false (a b : Nat) :
    (a <= b)%Nat -> (b < a)%Nat -> False.
  Proof.
    intros Hle Hlt.
    apply Nat_le_nat_le' in Hle.
    apply Nat_le_nat_le' in Hlt.
    cbn [nat_of_Nat] in Hlt.
    lia.
  Qed.

  Lemma Nat_lt_lt_false_by_nat_succ_le (a b n : Nat) :
    (nat_of_Nat b <= S (nat_of_Nat a))%nat ->
    (a < n)%Nat -> (n < b)%Nat -> False.
  Proof.
    intros Hab Hlo Hhi.
    apply Nat_le_nat_le' in Hlo.
    apply Nat_le_nat_le' in Hhi.
    cbn [nat_of_Nat] in Hlo, Hhi.
    lia.
  Qed.
End nat_notation.
Add Zify InjTyp Inj_Nat_Z.

Number Notation Nat Nat_of_num_uint Nat_to_num_uint (abstract after 5000) : Nat_scope.
(* Tell the kernel to unfold these wrappers early, to speed things up *)
#[global] Strategy -10000 [Nat_of_num_uint Nat_to_num_uint].

Fixpoint Nat_add n m :=
  match m with
  | 0 => n
  | Nat_succ p => Nat_succ (Nat_add n p)
  end.

Fixpoint Nat_mul n m :=
  match m with
  | 0 => 0
  | Nat_succ p => Nat_add (Nat_mul n p) n
  end.

Fixpoint Nat_pow n m :=
  match m with
    | 0 => 1
    | Nat_succ m => Nat_mul (Nat_pow n m) n
  end.

Register Nat_add as lean.Nat_add.
Register Nat_mul as lean.Nat_mul.
Register Nat_pow as lean.Nat_pow.

Lemma nat_of_Nat_add (n m : Nat) :
  nat_of_Nat (Nat_add n m) = (nat_of_Nat n + nat_of_Nat m)%nat.
Proof.
  induction m as [|m IH]; cbn.
  - rewrite PeanoNat.Nat.add_0_r; reflexivity.
  - rewrite IH; lia.
Qed.

Lemma nat_of_Nat_mul (n m : Nat) :
  nat_of_Nat (Nat_mul n m) = (nat_of_Nat n * nat_of_Nat m)%nat.
Proof.
  induction m as [|m IH]; cbn.
  - rewrite PeanoNat.Nat.mul_0_r; reflexivity.
  - rewrite nat_of_Nat_add, IH; lia.
Qed.

Lemma nat_of_Nat_pow (n m : Nat) :
  nat_of_Nat (Nat_pow n m) =
    PeanoNat.Nat.pow (nat_of_Nat n) (nat_of_Nat m).
Proof.
  induction m as [|m IH]; cbn.
  - reflexivity.
  - rewrite nat_of_Nat_mul, IH, PeanoNat.Nat.mul_comm; reflexivity.
Qed.

Fixpoint Nat_double_pow (k : nat) : Nat :=
  match k with
  | O => Nat_succ (double 0)
  | S k => double (Nat_double_pow k)
  end.

Lemma Nat_double_pow_succ (k : nat) :
  Logic.eq (double (Nat_double_pow k)) (Nat_double_pow (S k)).
Proof. reflexivity. Qed.

Definition Nat_pow2_63_literal : Nat := Nat_double_pow 63%nat.
Register Nat_pow2_63_literal as lean.Nat_pow2_63_literal.

Definition Nat_64_literal : Nat := Nat_of_nat 64%nat.
Register Nat_64_literal as lean.Nat_64_literal.

Fixpoint Nat_double_iter (k : nat) (n : Nat) : Nat :=
  match k with
  | O => n
  | S k => double (Nat_double_iter k n)
  end.

Definition Nat_0x11_double : Nat :=
  Nat_succ (Nat_double_iter 4%nat (Nat_succ (double 0))).

Definition Nat_0x110000_double : Nat :=
  Nat_double_iter 16%nat Nat_0x11_double.

Lemma nat_of_Nat_double (n : Nat) :
  nat_of_Nat (double n) = (2 * nat_of_Nat n)%nat.
Proof.
  induction n as [|n IH]; cbn.
  - reflexivity.
  - rewrite IH; lia.
Qed.

Lemma nat_of_Nat_double_pow (k : nat) :
  nat_of_Nat (Nat_double_pow k) = PeanoNat.Nat.pow 2 k.
Proof.
  induction k as [|k IH]; cbn [Nat_double_pow].
  - reflexivity.
  - rewrite nat_of_Nat_double, IH, PeanoNat.Nat.pow_succ_r'.
    reflexivity.
Qed.

Lemma nat_of_Nat_double_iter (k : nat) (n : Nat) :
  nat_of_Nat (Nat_double_iter k n) =
    (PeanoNat.Nat.pow 2 k * nat_of_Nat n)%nat.
Proof.
  induction k as [|k IH]; cbn [Nat_double_iter].
  - rewrite PeanoNat.Nat.mul_1_l; reflexivity.
  - rewrite nat_of_Nat_double, IH, PeanoNat.Nat.pow_succ_r'.
    rewrite PeanoNat.Nat.mul_assoc.
    rewrite (PeanoNat.Nat.mul_comm 2 (PeanoNat.Nat.pow 2 k)).
    reflexivity.
Qed.

Lemma nat_of_Nat_0x110000_double :
  nat_of_Nat Nat_0x110000_double = nat_of_Nat 0x110000.
Proof.
  unfold Nat_0x110000_double, Nat_0x11_double.
  rewrite nat_of_Nat_double_iter.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_double_iter.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_double.
  cbn [nat_of_Nat].
  unfold Nat_of_num_uint, Nat_of_N.
  rewrite nat2Natid.
  apply Nat2Z.inj.
  rewrite Nat2Z.inj_mul, Nat2Z.inj_succ, Nat2Z.inj_mul.
  rewrite !Nat2Z.inj_pow, N_nat_Z.
  vm_compute; reflexivity.
Qed.

Lemma Nat_lt_0x110000_of_lt_double_bound (n : Nat) :
  (n < Nat_0x110000_double)%Nat -> (n < 0x110000)%Nat.
Proof.
  intro H.
  eapply Nat_lt_congr_right_by_nat_of_Nat.
  - exact H.
  - exact nat_of_Nat_0x110000_double.
Qed.

Lemma Nat_le_double_right (n m : Nat) :
  (n <= m)%Nat -> (n <= double m)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  rewrite nat_of_Nat_double.
  lia.
Qed.

Lemma Nat_mul_pow6_lt_pow32_of_lt32 (n : Nat) :
  (n < 32)%Nat -> (Nat_mul n (Nat_pow 2 6) < Nat_pow 2 32)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, !nat_of_Nat_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 6) with (6 : nat) in *.
  change (nat_of_Nat 32) with (32 : nat) in *.
  assert (hn : (nat_of_Nat n < 32)%nat) by
    (change (S (nat_of_Nat n) <= 32)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (32 * PeanoNat.Nat.pow 2 6)%nat with
      (PeanoNat.Nat.pow 2 5 * PeanoNat.Nat.pow 2 6)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (5 + 6)%nat with (11 : nat).
    apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_mul_pow6_lt_double_pow11_of_lt32 (n : Nat) :
  (n < 32)%Nat -> (Nat_mul n (Nat_pow 2 6) < Nat_double_pow 11%nat)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, nat_of_Nat_pow, nat_of_Nat_double_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 6) with (6 : nat) in *.
  change (nat_of_Nat 32) with (32 : nat) in *.
  assert (hn : (nat_of_Nat n < 32)%nat) by
    (change (S (nat_of_Nat n) <= 32)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (32 * PeanoNat.Nat.pow 2 6)%nat with
      (PeanoNat.Nat.pow 2 5 * PeanoNat.Nat.pow 2 6)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (5 + 6)%nat with (11 : nat).
    reflexivity.
Qed.

Lemma Nat_mul_pow6_lt_double_pow32_of_lt32 (n : Nat) :
  (n < 32)%Nat -> (Nat_mul n (Nat_pow 2 6) < Nat_double_pow 32%nat)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, nat_of_Nat_pow, nat_of_Nat_double_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 6) with (6 : nat) in *.
  change (nat_of_Nat 32) with (32 : nat) in *.
  assert (hn : (nat_of_Nat n < 32)%nat) by
    (change (S (nat_of_Nat n) <= 32)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (32 * PeanoNat.Nat.pow 2 6)%nat with
      (PeanoNat.Nat.pow 2 5 * PeanoNat.Nat.pow 2 6)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (5 + 6)%nat with (11 : nat).
    apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_mul_pow12_lt_double_pow16_of_lt16 (n : Nat) :
  (n < 16)%Nat -> (Nat_mul n (Nat_pow 2 12) < Nat_double_pow 16%nat)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, nat_of_Nat_pow, nat_of_Nat_double_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 12) with (12 : nat) in *.
  change (nat_of_Nat 16) with (16 : nat) in *.
  assert (hn : (nat_of_Nat n < 16)%nat) by
    (change (S (nat_of_Nat n) <= 16)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (16 * PeanoNat.Nat.pow 2 12)%nat with
      (PeanoNat.Nat.pow 2 4 * PeanoNat.Nat.pow 2 12)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (4 + 12)%nat with (16 : nat).
    reflexivity.
Qed.

Lemma Nat_mul_pow12_lt_pow32_of_lt16 (n : Nat) :
  (n < 16)%Nat -> (Nat_mul n (Nat_pow 2 12) < Nat_pow 2 32)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, !nat_of_Nat_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 12) with (12 : nat) in *.
  change (nat_of_Nat 16) with (16 : nat) in *.
  change (nat_of_Nat 32) with (32 : nat) in *.
  assert (hn : (nat_of_Nat n < 16)%nat) by
    (change (S (nat_of_Nat n) <= 16)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (16 * PeanoNat.Nat.pow 2 12)%nat with
      (PeanoNat.Nat.pow 2 4 * PeanoNat.Nat.pow 2 12)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (4 + 12)%nat with (16 : nat).
    apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_mul_pow6_lt_double_pow12_of_lt64 (n : Nat) :
  (n < 64)%Nat -> (Nat_mul n (Nat_pow 2 6) < Nat_double_pow 12%nat)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, nat_of_Nat_pow, nat_of_Nat_double_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 6) with (6 : nat) in *.
  change (nat_of_Nat 64) with (64 : nat) in *.
  assert (hn : (nat_of_Nat n < 64)%nat) by
    (change (S (nat_of_Nat n) <= 64)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (64 * PeanoNat.Nat.pow 2 6)%nat with
      (PeanoNat.Nat.pow 2 6 * PeanoNat.Nat.pow 2 6)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (6 + 6)%nat with (12 : nat).
    reflexivity.
Qed.

Lemma Nat_mul_pow6_lt_pow32_of_lt64 (n : Nat) :
  (n < 64)%Nat -> (Nat_mul n (Nat_pow 2 6) < Nat_pow 2 32)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_mul, !nat_of_Nat_pow.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 2) with (2 : nat) in *.
  change (nat_of_Nat 6) with (6 : nat) in *.
  change (nat_of_Nat 64) with (64 : nat) in *.
  change (nat_of_Nat 32) with (32 : nat) in *.
  assert (hn : (nat_of_Nat n < 64)%nat) by
    (change (S (nat_of_Nat n) <= 64)%nat in h; exact h).
  eapply PeanoNat.Nat.lt_le_trans.
  - apply PeanoNat.Nat.mul_lt_mono_pos_r.
    + cbn; lia.
    + exact hn.
  - change (64 * PeanoNat.Nat.pow 2 6)%nat with
      (PeanoNat.Nat.pow 2 6 * PeanoNat.Nat.pow 2 6)%nat.
    rewrite <- PeanoNat.Nat.pow_add_r.
    change (6 + 6)%nat with (12 : nat).
    apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_add_zero_left (n : Nat) :
  Logic.eq (Nat_add Nat_zero n) n.
Proof.
  induction n; cbn [Nat_add]; rewrite ?IHn; reflexivity.
Qed.

Lemma Nat_add_succ_left (n m : Nat) :
  Logic.eq (Nat_add (Nat_succ n) m) (Nat_succ (Nat_add n m)).
Proof.
  induction m; cbn [Nat_add]; rewrite ?IHm; reflexivity.
Qed.

Lemma Nat_add_self_eq_double (n : Nat) :
  Logic.eq (Nat_add n n) (double n).
Proof.
  induction n; cbn [Nat_add double].
  - reflexivity.
  - rewrite Nat_add_succ_left, IHn; reflexivity.
Qed.

Lemma Nat_mul_two_eq_double (n : Nat) :
  Logic.eq (Nat_mul n 2) (double n).
Proof.
  cbn [Nat_mul].
  rewrite Nat_add_zero_left.
  exact (Nat_add_self_eq_double n).
Qed.

Lemma Nat_mul_two_eq_add_self (n : Nat) :
  Logic.eq (Nat_mul n 2) (Nat_add n n).
Proof.
  rewrite Nat_mul_two_eq_double, <- Nat_add_self_eq_double.
  reflexivity.
Qed.

Lemma Nat_two_mul_eq_double (n : Nat) :
  Logic.eq (Nat_mul 2 n) (double n).
Proof.
  rewrite <- (Nat2natid (Nat_mul 2 n)), <- (Nat2natid (double n)).
  f_equal.
  rewrite nat_of_Nat_mul, nat_of_Nat_double.
  cbn [nat_of_Nat].
  lia.
Qed.

Lemma Nat_pow_two_eq_double_pow_nat (k : nat) :
  Logic.eq (Nat_pow 2 (Nat_of_nat k)) (Nat_double_pow k).
Proof.
  induction k as [|k IH]; cbn [Nat_of_nat Nat_pow Nat_double_pow].
  - reflexivity.
  - rewrite IH. apply Nat_mul_two_eq_double.
Qed.

Lemma Nat_pow_two_eq_pow2_63_literal :
  Logic.eq (Nat_pow 2 (Nat_of_nat 63%nat)) Nat_pow2_63_literal.
Proof.
  unfold Nat_pow2_63_literal.
  exact (Nat_pow_two_eq_double_pow_nat 63%nat).
Qed.

Lemma Nat_double_pow_pos (k : nat) : (0 < Nat_double_pow k)%Nat.
Proof.
  induction k as [|k IH]; cbn [Nat_double_pow].
  - apply Nat_le_refl.
  - apply Nat_le_double_right. exact IH.
Qed.

Lemma Nat_lt_double_of_pos (n : Nat) :
  (0 < n)%Nat -> (n < double n)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  rewrite nat_of_Nat_double.
  lia.
Qed.

Lemma Nat_double_pow_lt_add_succ (k d : nat) :
  (Nat_double_pow k < Nat_double_pow (S d + k))%Nat.
Proof.
  induction d as [|d IH].
  - change (Nat_double_pow k < double (Nat_double_pow k))%Nat.
    apply Nat_lt_double_of_pos.
    apply Nat_double_pow_pos.
  - change
      (Nat_double_pow k < double (Nat_double_pow (S d + k)))%Nat.
    apply Nat_le_double_right.
    exact IH.
Qed.

Lemma Nat_pow32_lt_pow64 :
  (Nat_pow 2 32 < Nat_pow 2 64)%Nat.
Proof.
  change
    (Nat_pow 2 (Nat_of_nat 32%nat) <
     Nat_pow 2 (Nat_of_nat 64%nat))%Nat.
  rewrite (Nat_pow_two_eq_double_pow_nat 32%nat).
  rewrite (Nat_pow_two_eq_double_pow_nat 64%nat).
  exact (Nat_double_pow_lt_add_succ 32%nat 31%nat).
Qed.

Lemma Nat_six_lt_32 : (6 < 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  lia.
Qed.

Lemma Nat_one_lt_two : (1 < 2)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  lia.
Qed.

Lemma Nat_15_lt_pow8 : (15 < Nat_pow 2 8)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 8) with (8 : nat).
  change (nat_of_Nat 15) with (15 : nat).
  cbn; lia.
Qed.

Lemma Nat_31_lt_pow8 : (31 < Nat_pow 2 8)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 8) with (8 : nat).
  change (nat_of_Nat 31) with (31 : nat).
  cbn; lia.
Qed.

Lemma Nat_63_lt_pow8 : (63 < Nat_pow 2 8)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 8) with (8 : nat).
  change (nat_of_Nat 63) with (63 : nat).
  cbn; lia.
Qed.

Lemma Nat_128_lt_pow8 : (128 < Nat_pow 2 8)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 8) with (8 : nat).
  change (nat_of_Nat 128) with (128 : nat).
  cbn; lia.
Qed.

Lemma Nat_lt_16_of_le_15 (n : Nat) :
  (n <= 15)%Nat -> (n < 16)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  lia.
Qed.

Lemma Nat_lt_32_of_le_31 (n : Nat) :
  (n <= 31)%Nat -> (n < 32)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  lia.
Qed.

Lemma Nat_lt_64_of_le_63 (n : Nat) :
  (n <= 63)%Nat -> (n < 64)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  lia.
Qed.

Lemma Nat_twelve_lt_32 : (12 < 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  lia.
Qed.

Lemma Nat_six_lt_pow32 : (6 < Nat_pow 2 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 6) with (6 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 3).
  - change (7 <= PeanoNat.Nat.pow 2 3)%nat.
    cbn; lia.
  - apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_twelve_lt_pow32 : (12 < Nat_pow 2 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 12) with (12 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 4).
  - change (13 <= PeanoNat.Nat.pow 2 4)%nat.
    cbn; lia.
  - apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_127_lt_pow32 : (127 < Nat_pow 2 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 127) with (127 : nat).
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 7).
  - change (128 <= PeanoNat.Nat.pow 2 7)%nat.
    cbn; lia.
  - apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_lt_pow32_of_le_127 (n : Nat) :
  (n <= 127)%Nat -> (n < Nat_pow 2 32)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := 128%nat).
  - lia.
  - eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 7).
    + change (128 <= PeanoNat.Nat.pow 2 7)%nat.
      cbn; lia.
    + apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_le_0xffff_of_le_127 (n : Nat) :
  (n <= 127)%Nat -> (n <= 0xffff)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  eapply PeanoNat.Nat.le_trans with (m := 127%nat).
  - exact h.
  - apply Nat2Z.inj_le; vm_compute; discriminate.
Qed.

Lemma Nat_le_0xffff_of_le_2047 (n : Nat) :
  (n <= 2047)%Nat -> (n <= 0xffff)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  eapply PeanoNat.Nat.le_trans with (m := 2047%nat).
  - exact h.
  - apply Nat2Z.inj_le; vm_compute; discriminate.
Qed.

Lemma Nat_le_0x10000_of_lt_0xffff (n : Nat) :
  (0xffff < n)%Nat -> (0x10000 <= n)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in h.
  assert (Heq : nat_of_Nat 0x10000 = S (nat_of_Nat 0xffff)).
  { apply Nat2Z.inj; vm_compute; reflexivity. }
  rewrite Heq.
  exact h.
Qed.

Lemma Nat_le_0x10ffff_of_lt_0xd800 (n : Nat) :
  (n < 0xd800)%Nat -> (n <= 0x10ffff)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 0xd800) with (55296 : nat) in h.
  change (nat_of_Nat 0x10ffff) with (1114111 : nat).
  eapply PeanoNat.Nat.le_trans with (m := 55296%nat).
  - eapply PeanoNat.Nat.le_trans.
    + apply PeanoNat.Nat.le_succ_diag_r.
    + exact h.
  - apply Nat2Z.inj_le; vm_compute; discriminate.
Qed.

Lemma Nat_le_0x10ffff_of_lt_0x110000 (n : Nat) :
  (n < 0x110000)%Nat -> (n <= 0x10ffff)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  cbn [nat_of_Nat] in *.
  change (nat_of_Nat 0x110000) with (S (1114111 : nat)) in h.
  change (nat_of_Nat 0x10ffff) with (1114111 : nat).
  apply PeanoNat.Nat.succ_le_mono in h.
  exact h.
Qed.

Lemma Nat_0xd800_lt_pow32 : (0xd800 < Nat_pow 2 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 0xd800) with (55296 : nat).
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 16).
  - apply Nat2Z.inj_le; vm_compute; discriminate.
  - apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_0xdfff_lt_pow32 : (0xdfff < Nat_pow 2 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 0xdfff) with (57343 : nat).
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 16).
  - apply Nat2Z.inj_le; vm_compute; discriminate.
  - apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_0x110000_lt_pow32 : (0x110000 < Nat_pow 2 32)%Nat.
Proof.
  apply nat_le_Nat_le.
  cbn [nat_of_Nat].
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  change (nat_of_Nat 0x110000) with (1114112 : nat).
  change (nat_of_Nat 2) with (2 : nat).
  change (nat_of_Nat 32) with (32 : nat).
  eapply PeanoNat.Nat.le_trans with (m := PeanoNat.Nat.pow 2 21).
  - apply Nat2Z.inj_le; vm_compute; discriminate.
  - apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma Nat_0xd800_le_succ_0x10ffff :
  (nat_of_Nat 0xd800 <= S (nat_of_Nat 0x10ffff))%nat.
Proof.
  apply Nat2Z.inj_le; vm_compute; discriminate.
Qed.

Lemma Nat_0x110000_le_succ_0x10ffff :
  (nat_of_Nat 0x110000 <= S (nat_of_Nat 0x10ffff))%nat.
Proof.
  apply Nat2Z.inj_le; vm_compute; discriminate.
Qed.

#[local] Set Warnings "-abstract-large-number".
Definition UInt32_size : Nat := Nat_pow 2 32.
Register UInt32_size as lean.UInt32_size.

Definition UInt64_size : Nat := Nat_pow 2 64.
Register UInt64_size as lean.UInt64_size.

Definition System_Platform_numBits : Nat := 64.
Register System_Platform_numBits as lean.System_Platform_numBits.

Lemma System_Platform_numBits_eq :
  Or (@eq Nat System_Platform_numBits 32)
     (@eq Nat System_Platform_numBits 64).
Proof.
  apply Or_inr.
  reflexivity.
Qed.
Register System_Platform_numBits_eq as lean.System_Platform_numBits_eq.

Definition USize_size : Nat := Nat_pow 2 System_Platform_numBits.
Register USize_size as lean.USize_size.

Lemma USize_size_pos : (0 < USize_size)%Nat.
Proof.
  unfold USize_size, System_Platform_numBits.
  change (0 < Nat_pow 2 (Nat_of_nat 64%nat))%Nat.
  rewrite Nat_pow_two_eq_double_pow_nat.
  exact (Nat_double_pow_pos 64%nat).
Qed.

Record Fin@{} (n : Nat) := Fin_mk { val : Nat; isLt : (val < n)%Nat }.
Register Fin as lean.Fin.

Record BitVec@{} (w : Nat) := BitVec_ofFin { toFin : Fin (Nat_pow 2 w) }.
Register BitVec as lean.BitVec.

Record USize@{} := USize_ofBitVec { USize_toBitVec : BitVec System_Platform_numBits }.
Register USize as lean.USize.
Register USize_toBitVec as lean.USize_toBitVec.

Definition USize_toNat (n : USize) : Nat :=
  n.(USize_toBitVec).(toFin _).(val _).
Register USize_toNat as lean.USize_toNat.

Lemma USize_le_size : (UInt32_size <= USize_size)%Nat.
Proof.
  unfold UInt32_size, USize_size, System_Platform_numBits.
  apply nat_le_Nat_le.
  rewrite !nat_of_Nat_pow.
  cbn [nat_of_Nat].
  apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.
Register USize_le_size as lean.USize_le_size.

Lemma USize_size_le : (USize_size <= UInt64_size)%Nat.
Proof.
  unfold USize_size, UInt64_size, System_Platform_numBits.
  apply nat_le_Nat_le.
  rewrite !nat_of_Nat_pow.
  cbn [nat_of_Nat].
  apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.
Register USize_size_le as lean.USize_size_le.

Lemma USize_lt_size_of_lt_32 (n : Nat) :
  (n < Nat_double_pow 32%nat)%Nat -> (n < USize_size)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  rewrite nat_of_Nat_double_pow in h.
  eapply PeanoNat.Nat.lt_le_trans.
  - exact h.
  - unfold USize_size, System_Platform_numBits.
    rewrite nat_of_Nat_pow.
    cbn [nat_of_Nat].
    apply PeanoNat.Nat.pow_le_mono_r; lia.
Qed.

Lemma nat_pow_two_pred (k : nat) :
  k <> O ->
  PeanoNat.Nat.pow 2 k =
    (2 * PeanoNat.Nat.pow 2 (PeanoNat.Nat.pred k))%nat.
Proof.
  destruct k as [|k].
  - lia.
  - intros _.
    cbn [PeanoNat.Nat.pred].
    rewrite PeanoNat.Nat.pow_succ_r'.
    reflexivity.
Qed.

Ltac solve_Nat_double_tower_bound :=
  lazymatch goal with
  | |- (nat_of_Nat (double ?x) <= PeanoNat.Nat.pow 2 ?k)%nat =>
      rewrite nat_of_Nat_double;
      rewrite (nat_pow_two_pred k) by lia;
      apply PeanoNat.Nat.mul_le_mono_l;
      let k' := eval cbn in (PeanoNat.Nat.pred k) in
      change (nat_of_Nat x <= PeanoNat.Nat.pow 2 k')%nat;
      solve_Nat_double_tower_bound
  | |- (nat_of_Nat (Nat_succ (double 0)) <= PeanoNat.Nat.pow 2 ?k)%nat =>
      cbn [nat_of_Nat double];
      change (1 <= PeanoNat.Nat.pow 2 k)%nat;
      change 1%nat with (PeanoNat.Nat.pow 2 0);
      apply PeanoNat.Nat.pow_le_mono_r; lia
  end.

Lemma USize_double_pow32_literal_le_size :
  (ltac:(
     let t := eval cbn [Nat_double_pow] in (Nat_double_pow 32%nat) in
     exact t) <= USize_size)%Nat.
Proof.
  apply nat_le_Nat_le.
  unfold USize_size, System_Platform_numBits.
  rewrite nat_of_Nat_pow.
  cbn [nat_of_Nat].
  solve_Nat_double_tower_bound.
Qed.

Lemma USize_lt_size_of_lt_32_literal (n : Nat) :
  (n <
   ltac:(
     let t := eval cbn [Nat_double_pow] in (Nat_double_pow 32%nat) in
     exact t))%Nat ->
  (n < USize_size)%Nat.
Proof.
  intro h.
  apply nat_le_Nat_le.
  apply Nat_le_nat_le' in h.
  pose proof USize_double_pow32_literal_le_size as hb.
  apply Nat_le_nat_le' in hb.
  eapply PeanoNat.Nat.le_trans; [ exact h | exact hb ].
Qed.

Record UInt8@{} := UInt8_ofBitVec { toBitVec8 : BitVec 8 }.
Register UInt8 as lean.UInt8.

Record UInt32@{} := UInt32_ofBitVec { toBitVec : BitVec 32 }.
Register UInt32 as lean.UInt32.
Register toBitVec as lean.toBitVec.
Lemma UInt32_size_to_pow32 :
  forall n : Nat, n < UInt32_size -> n < Nat_pow 2 32.
Proof.
  unfold UInt32_size.
  exact (fun _ h => h).
Qed.
Definition UInt32_ofNatLT (n : Nat) (h : n < UInt32_size) : UInt32 :=
  UInt32_ofBitVec
    (BitVec_ofFin 32 (Fin_mk (Nat_pow 2 32) n (UInt32_size_to_pow32 n h))).
Register UInt32_ofNatLT as lean.UInt32_ofNatLT.

Record UInt64@{} := UInt64_ofBitVec { toBitVec64 : BitVec 64 }.
Register UInt64 as lean.UInt64.

Lemma UInt64_size_to_pow64 :
  forall n : Nat, n < UInt64_size -> n < Nat_pow 2 64.
Proof.
  unfold UInt64_size.
  exact (fun _ h => h).
Qed.
Definition UInt64_ofNatLT (n : Nat) (h : n < UInt64_size) : UInt64 :=
  UInt64_ofBitVec
    (BitVec_ofFin 64
      (Fin_mk (Nat_pow 2 64) n (UInt64_size_to_pow64 n h))).
Register UInt64_ofNatLT as lean.UInt64_ofNatLT.

Section strings.
  Import ZArith NArith Lia Zify ZifyBool.
  Variant InvalidUInt32 (n : N) : Set := invalid_uint32.
  Variant InvalidChar (n : N) : Set := invalid_char.
  #[local] Set Warnings "-abstract-large-number".

  Lemma Nat_lt_to_N (n : N) (m : N) : (n <? m)%N = true -> Nat_of_N n < Nat_of_N m.
  Proof.
    cbv [N_of_Nat Nat_of_N].
    intro H; apply nat_le_Nat_le.
    cbn [nat_of_Nat].
    rewrite ?nat2Natid.
    lia.
  Qed.

  Lemma Nat_lt_to_N_l (n : Nat) (m : N) : (N_of_Nat n <? m)%N = true -> n < Nat_of_N m.
  Proof.
    cbv [N_of_Nat Nat_of_N].
    intro H; apply nat_le_Nat_le.
    cbn [nat_of_Nat].
    rewrite nat2Natid.
    lia.
  Qed.

  Lemma Nat_lt_to_N_r (n : N) (m : Nat) : (n <? N_of_Nat m)%N = true -> Nat_of_N n < m.
  Proof.
    cbv [N_of_Nat Nat_of_N].
    intro H; apply nat_le_Nat_le.
    cbn [nat_of_Nat].
    rewrite nat2Natid.
    lia.
  Qed.

  (* Section with_or. *)
    (* Context (Or : SProp -> SProp -> SProp)
            (Or_inl : forall P Q, P -> Or P Q)
            (Or_inr : forall P Q, Q -> Or P Q)
            (And : SProp -> SProp -> SProp)
            (And_intro : forall P Q, P -> Q -> And P Q). *)
  #[local] Set Warnings "-notation-overridden".
  #[local] Infix "\/" := Or : type_scope.
  #[local] Infix "/\" := And : type_scope.
  #[local] Open Scope Nat_scope.

  Definition Nat_isValidChar (n : Nat) : SProp
    := n < 0xd800 \/ (0xdfff < n /\ n < 0x110000).

<<<<<<< HEAD
  Definition isValidChar_UInt32_match_1_1
    (n : Nat) (motive : Nat_isValidChar n -> SProp)
    (h : Nat_isValidChar n)
    (h_1 : forall h : n < 0xd800, motive (Or_inl _ _ h))
    (h_2 : forall (left : 0xdfff < n) (right : n < 0x110000),
      motive (Or_inr _ _ (And_intro _ _ left right)))
    : motive h
    := match h with
       | Or_inl _ _ h => h_1 h
       | Or_inr _ _ h => h_2 (left _ _ h) (right _ _ h)
       end.

  Lemma isValidChar_UInt32 (n : Nat) (h : Nat_isValidChar n) : n < UInt32_size.
  Proof.
    unfold UInt32_size.
    destruct h as [h | h].
    - apply nat_le_Nat_le.
      apply Nat_le_nat_le' in h.
      pose proof Nat_0xd800_lt_pow32 as Hbound.
      apply Nat_le_nat_le' in Hbound.
      cbn [nat_of_Nat] in h, Hbound.
      eapply PeanoNat.Nat.le_trans; [exact h |].
      eapply PeanoNat.Nat.le_trans.
      + apply PeanoNat.Nat.le_succ_diag_r.
      + exact Hbound.
    - destruct h as [_ h].
      apply nat_le_Nat_le.
      apply Nat_le_nat_le' in h.
      pose proof Nat_0x110000_lt_pow32 as Hbound.
      apply Nat_le_nat_le' in Hbound.
      cbn [nat_of_Nat] in h, Hbound.
      eapply PeanoNat.Nat.le_trans; [exact h |].
      eapply PeanoNat.Nat.le_trans.
      + apply PeanoNat.Nat.le_succ_diag_r.
      + exact Hbound.
  Qed.
=======
  Record Char_legacy@{} := Char_legacy_mk
  { val1_legacy : UInt32_legacy;
    valid_legacy : Nat_isValidChar val1_legacy.(val0).(val _) }.
>>>>>>> parent of dec4a1b (Predeclare modern Char construction helpers)

  Record Char@{} := Char_mk
  { val1 : UInt32; valid : Nat_isValidChar val1.(toBitVec).(toFin _).(val _) }.

  Definition check_N_isValidChar (n : N) : bool
    := ((n <? 0xd800) || ((0xdfff <? n) && (n <? 0x110000)))%N%bool.

  Lemma Nat_nat_add n m : Nat_of_nat (n + m) = Nat_add (Nat_of_nat n) (Nat_of_nat m).
  Proof.
    rewrite Nat.add_comm.
    induction m. 
    - reflexivity.
    - simpl. now f_equal.
  Qed.

  Lemma Nat_nat_mul n m : Nat_of_nat (n * m) = Nat_mul (Nat_of_nat n) (Nat_of_nat m).
  Proof.
    rewrite Nat.mul_comm.
    induction m; simpl.
    - reflexivity. 
    - rewrite Nat.add_comm, Nat_nat_add. now f_equal.
  Qed. 
  
  Lemma Nat_nat_pow n m : Nat_of_nat (n ^ m) = Nat_pow (Nat_of_nat n) (Nat_of_nat m).
  Proof.
    induction m; simpl.
    - reflexivity. 
    - rewrite Nat.mul_comm, Nat_nat_mul. now f_equal. 
  Qed.
  
  Lemma Nat_pow_comm (n : N) : Nat_of_N (2 ^ n) = Nat_pow 2 (Nat_of_N n).
  Proof.
    unfold Nat_of_N. rewrite N2Nat.inj_pow.
    eapply Nat_nat_pow. 
  Qed.
<<<<<<< HEAD

  Lemma Nat_pow_two_eq_of_N_pow (n p : N) :
    Logic.eq (2 ^ n)%N p -> @eq Nat (Nat_pow 2 (Nat_of_N n)) (Nat_of_N p).
  Proof.
    intro H.
    apply lean_eq_of_logic_eq.
    rewrite <- Nat_pow_comm.
    now rewrite H.
  Qed.

  Lemma Nat_pow_two_32_eq_0x100000000 :
    @eq Nat (Nat_pow 2 32) 0x100000000.
  Proof.
    change (@eq Nat (Nat_pow 2 (Nat_of_N 32%N)) (Nat_of_N 0x100000000%N)).
    apply Nat_pow_two_eq_of_N_pow.
    vm_compute; reflexivity.
  Qed.

  Lemma Nat_pow_two_64_eq_0x10000000000000000 :
    @eq Nat (Nat_pow 2 64) 0x10000000000000000.
  Proof.
    change (@eq Nat (Nat_pow 2 (Nat_of_N 64%N)) (Nat_of_N 0x10000000000000000%N)).
    apply Nat_pow_two_eq_of_N_pow.
    vm_compute; reflexivity.
  Qed.

  Lemma Nat_pow_two_eq_0x100000000_of_eq_32 (n : Nat) :
    @eq Nat n (Nat_of_N 32%N) ->
    @eq Nat (Nat_pow 2 n) (Nat_of_N 0x100000000%N).
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) (Nat_of_N 0x100000000%N)) H).
    apply Nat_pow_two_eq_of_N_pow.
    vm_compute; reflexivity.
  Qed.

  Lemma Nat_pow_two_eq_0x100000000_of_eq_32_lit (n : Nat) :
    @eq Nat n 32 ->
    @eq Nat (Nat_pow 2 n) 0x100000000.
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) 0x100000000) H).
    exact Nat_pow_two_32_eq_0x100000000.
  Qed.

  Lemma Nat_pow_two_eq_0x10000000000000000_of_eq_64 (n : Nat) :
    @eq Nat n (Nat_of_N 64%N) ->
    @eq Nat (Nat_pow 2 n) (Nat_of_N 0x10000000000000000%N).
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) (Nat_of_N 0x10000000000000000%N)) H).
    apply Nat_pow_two_eq_of_N_pow.
    vm_compute; reflexivity.
  Qed.

  Lemma Nat_pow_two_eq_0x10000000000000000_of_eq_64_lit (n : Nat) :
    @eq Nat n 64 ->
    @eq Nat (Nat_pow 2 n) 0x10000000000000000.
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) 0x10000000000000000) H).
    exact Nat_pow_two_64_eq_0x10000000000000000.
  Qed.

  Lemma Nat_pow_two_32_eq_double_pow :
    @eq Nat (Nat_pow 2 32) (Nat_double_pow 32).
  Proof.
    change (@eq Nat (Nat_pow 2 (Nat_of_nat 32%nat)) (Nat_double_pow 32%nat)).
    apply lean_eq_of_logic_eq.
    exact (Nat_pow_two_eq_double_pow_nat 32%nat).
  Qed.

  Lemma Nat_pow_two_eq_double_pow32_of_eq_32 (n : Nat) :
    @eq Nat n 32 ->
    @eq Nat (Nat_pow 2 n) (Nat_double_pow 32).
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) (Nat_double_pow 32)) H).
    exact Nat_pow_two_32_eq_double_pow.
  Qed.

  Lemma Nat_pow_two_64_eq_double_pow :
    @eq Nat (Nat_pow 2 64) (Nat_double_pow 64).
  Proof.
    change (@eq Nat (Nat_pow 2 (Nat_of_nat 64%nat)) (Nat_double_pow 64%nat)).
    apply lean_eq_of_logic_eq.
    exact (Nat_pow_two_eq_double_pow_nat 64%nat).
  Qed.

  Lemma Nat_pow_two_eq_double_pow64_of_eq_64 (n : Nat) :
    @eq Nat n 64 ->
    @eq Nat (Nat_pow 2 n) (Nat_double_pow 64).
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) (Nat_double_pow 64)) H).
    exact Nat_pow_two_64_eq_double_pow.
  Qed.

  Lemma Nat_pow_two_eq_pow32_of_eq_32 (n : Nat) :
    @eq Nat n 32 ->
    @eq Nat (Nat_pow 2 n) (Nat_pow 2 32).
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) (Nat_pow 2 32)) H).
    reflexivity.
  Qed.

  Lemma Nat_pow_two_eq_pow64_of_eq_64 (n : Nat) :
    @eq Nat n 64 ->
    @eq Nat (Nat_pow 2 n) (Nat_pow 2 64).
  Proof.
    intro H.
    eapply (eq_mpr_sprop
      (fun m => @eq Nat (Nat_pow 2 m) (Nat_pow 2 64)) H).
    reflexivity.
  Qed.

  Lemma USize_size_eq_of_numBits (n : Nat) :
    Or (@eq Nat n 32) (@eq Nat n 64) ->
    Or (@eq Nat (Nat_pow 2 n) UInt32_size)
       (@eq Nat (Nat_pow 2 n) UInt64_size).
  Proof.
    intro H.
    destruct H as [H | H].
    - apply Or_inl.
      unfold UInt32_size.
      exact (Nat_pow_two_eq_pow32_of_eq_32 n H).
    - apply Or_inr.
      unfold UInt64_size.
      exact (Nat_pow_two_eq_pow64_of_eq_64 n H).
  Qed.
  Register USize_size_eq_of_numBits as lean.USize_size_eq_of_numBits.

  Lemma USize_size_eq :
    Or (@eq Nat USize_size UInt32_size)
       (@eq Nat USize_size UInt64_size).
  Proof.
    unfold USize_size.
    exact (USize_size_eq_of_numBits
      System_Platform_numBits System_Platform_numBits_eq).
  Qed.
  Register USize_size_eq as lean.USize_size_eq.

  Lemma Nat_lt_to_N_pow_l (n : Nat) (m : N) :
    (N_of_Nat n <? 2 ^ m)%N = true -> n < Nat_pow 2 (Nat_of_N m).
  Proof.
    rewrite <- Nat_pow_comm. eapply Nat_lt_to_N_l.
  Qed.

  Lemma N_ltb_of_Nat_lt_to_N (n : Nat) (m : N) :
    n < Nat_of_N m -> (N_of_Nat n <? m)%N = true.
  Proof.
    intro H.
    apply N.ltb_lt.
    apply N2Z.inj_lt.
    cbv [N_of_Nat].
    rewrite nat_N_Z.
    rewrite <- (N2Nat.id m).
    rewrite nat_N_Z.
    apply Nat_le_nat_le' in H.
    cbv [Nat_of_N] in H.
    cbn [nat_of_Nat] in H.
    rewrite nat2Natid in H.
    lia.
  Qed.

  Lemma Nat_lt_0x110000_of_lt_0x10000 (n : Nat) :
    (n < 0x10000)%Nat -> (n < 0x110000)%Nat.
  Proof.
    intro h.
    unfold Nat_of_num_uint in *.
    change (n < Nat_of_N 0x110000%N)%Nat.
    apply Nat_lt_to_N_l.
    apply N.ltb_lt.
    eapply N.lt_trans.
    - apply N.ltb_lt.
      apply (N_ltb_of_Nat_lt_to_N n 0x10000%N).
      change (n < Nat_of_N 0x10000%N)%Nat in h.
      exact h.
    - vm_compute. reflexivity.
  Qed.

  Lemma Nat_lt_0x110000_of_lt_pow2_16 (n : Nat) :
    (n < Nat_pow 2 16)%Nat -> (n < 0x110000)%Nat.
  Proof.
    intro h.
    unfold Nat_of_num_uint in *.
    change (n < Nat_pow 2 (Nat_of_N 16%N))%Nat in h.
    rewrite <- Nat_pow_comm in h.
    change (n < Nat_of_N 0x110000%N)%Nat.
    apply Nat_lt_to_N_l.
    apply N.ltb_lt.
    eapply N.lt_trans.
    - apply N.ltb_lt.
      apply (N_ltb_of_Nat_lt_to_N n (2 ^ 16)%N).
      exact h.
    - vm_compute. reflexivity.
  Qed.

  Lemma Nat_mul_pow6_lt_0x100000000_of_lt32 (n : Nat) :
    (n < 32)%Nat -> (Nat_mul n (Nat_pow 2 6) < 0x100000000)%Nat.
  Proof.
    intro h.
    change (Nat_mul n (Nat_pow 2 6) < Nat_of_N 0x100000000%N)%Nat.
    apply Nat_lt_to_N_l.
    apply N.ltb_lt.
    cbv [N_of_Nat].
    rewrite nat_of_Nat_mul, nat_of_Nat_pow.
    cbn [nat_of_Nat] in *.
    change (nat_of_Nat 2) with (2 : nat) in *.
    change (nat_of_Nat 6) with (6 : nat) in *.
    change (nat_of_Nat 32) with (32 : nat) in *.
    apply Nat_le_nat_le' in h.
    change (S (nat_of_Nat n) <= 32)%nat in h.
    apply N2Z.inj_lt.
    rewrite nat_N_Z, Nat2Z.inj_mul.
    change (Z.of_nat (PeanoNat.Nat.pow 2 6)) with 64%Z.
    change (Z.of_N 0x100000000%N) with 4294967296%Z.
    lia.
  Qed.

  Definition UInt8_toNat (n : UInt8) : Nat :=
    n.(toBitVec8).(toFin _).(val _).

  Lemma UInt8_toUInt32_isLt (n : UInt8) :
    UInt8_toNat n < Nat_pow 2 32.
  Proof.
    unfold UInt8_toNat.
    destruct n as [bv].
    destruct bv as [f].
    destruct f as [v h].
    change (v < Nat_pow 2 (Nat_of_N 32)).
    apply Nat_lt_to_N_pow_l.
    apply N.ltb_lt.
    eapply N.lt_trans.
    - apply N.ltb_lt.
      apply (N_ltb_of_Nat_lt_to_N v (2 ^ 8)).
      change (v < Nat_pow 2 (Nat_of_N 8)) in h.
      exact h.
    - vm_compute. reflexivity.
  Qed.

  Definition UInt8_toUInt32 (n : UInt8) : UInt32 :=
    UInt32_ofBitVec
      (BitVec_ofFin 32
        (Fin_mk (Nat_pow 2 32) (UInt8_toNat n)
          (UInt8_toUInt32_isLt n))).

  Lemma isValidChar_pow32 (n : Nat) (h : Nat_isValidChar n) : n < Nat_pow 2 32.
  Proof.
    destruct h as [h | h].
    - change (n < Nat_pow 2 (Nat_of_N 32)).
      apply Nat_lt_to_N_pow_l.
      apply N.ltb_lt.
      eapply N.lt_trans.
      + apply N.ltb_lt.
        apply (N_ltb_of_Nat_lt_to_N n 0xd800).
        exact h.
      + vm_compute. reflexivity.
    - destruct h as [_ h].
      change (n < Nat_pow 2 (Nat_of_N 32)).
      apply Nat_lt_to_N_pow_l.
      apply N.ltb_lt.
      eapply N.lt_trans.
      + apply N.ltb_lt.
        apply (N_ltb_of_Nat_lt_to_N n 0x110000).
        exact h.
      + vm_compute. reflexivity.
  Qed.

  Definition Char_ofNatAux (n : Nat) (h : Nat_isValidChar n) : Char :=
    Char_mk
      (UInt32_ofBitVec
        (BitVec_ofFin 32 (Fin_mk (Nat_pow 2 32) n (isValidChar_pow32 n h))))
      h.
=======
>>>>>>> parent of dec4a1b (Predeclare modern Char construction helpers)
  
  Lemma Nat_lt_to_N_pow (n : N) (m : N) : (n <? 2 ^ m)%N = true -> Nat_of_N n < Nat_pow 2 (Nat_of_N m).
  Proof.
    rewrite <- Nat_pow_comm. eapply Nat_lt_to_N.
  Qed.

  Definition Fin_mk_N_pow (n : N) (val : N) (isLt : (val <? 2 ^ n)%N = true) : Fin (Nat_pow 2 (Nat_of_N n))
    := Fin_mk (Nat_pow 2 (Nat_of_N n)) (Nat_of_N val) (Nat_lt_to_N_pow val n isLt).

  Definition UInt32_mk_N (val : N) (isLt : (val <? 0x100000000)%N = true) : UInt32
    := UInt32_ofBitVec (BitVec_ofFin 32 (Fin_mk_N_pow 32 val isLt)).

  Lemma Nat_isValidChar_mk_N (n : N) (isLt : check_N_isValidChar n = true)
    : Nat_isValidChar (Nat_of_N n).
  Proof.
    cbv [Nat_isValidChar Nat_of_num_uint check_N_isValidChar] in *.
    pose proof (Nat_lt_to_N n 0xd800) as H1.
    pose proof (Nat_lt_to_N 0xdfff n) as H2.
    pose proof (Nat_lt_to_N n 0x110000) as H3.
    destruct N.ltb; cbn [orb] in *;
    [ | destruct N.ltb; cbn [andb] in *; [ | exfalso; congruence ] ];
    [ | destruct N.ltb; cbn [andb] in *; [ | exfalso; congruence ] ];
    [ apply Or_inl, nat_le_Nat_le; revert H1 | apply Or_inr, And_intro; apply nat_le_Nat_le; [ revert H2 | revert H3 ] ];
    clear.
    all: cbv [Nat_of_N Nat_of_num_uint].
    all: intro H; specialize (H Logic.eq_refl).
    all: apply Nat_le_nat_le' in H.
    1: etransitivity; [ exact H | ].
    2: etransitivity; [ | exact H ].
    3: etransitivity; [ exact H | ].
    all: clear.
    all: zify; clear.
    all: cbn [nat_of_Nat]; rewrite ?nat2Natid, ?Nat2Z.inj_succ, ?N_nat_Z.
    all: vm_compute; congruence.
  Qed.

  Definition Char_mk_N (val : N) (isLt : ((val <? 0x100000000)%N && check_N_isValidChar val)%bool = true) : Char
    := Char_mk (UInt32_mk_N val (proj1 (andb_prop _ _ isLt))) (Nat_isValidChar_mk_N val (proj2 (andb_prop _ _ isLt))).

<<<<<<< HEAD
  Lemma Nat_of_N_N_of_Nat (n : Nat) : Nat_of_N (N_of_Nat n) = n.
  Proof.
    cbv [Nat_of_N N_of_Nat].
    rewrite Nat2N.id.
    apply Nat2natid.
  Qed.

  Lemma Nat_isValidChar_of_check_N (n : Nat) :
    check_N_isValidChar (N_of_Nat n) = true -> Nat_isValidChar n.
  Proof.
    intro H.
    rewrite <- Nat_of_N_N_of_Nat.
    apply Nat_isValidChar_mk_N.
    exact H.
  Qed.

  Lemma Nat_isValidChar_zero : Nat_isValidChar 0.
  Proof.
    change (Nat_isValidChar (Nat_of_N 0)).
    apply Nat_isValidChar_mk_N.
    vm_compute. reflexivity.
  Qed.

  Definition Char_ofNat (n : Nat) : Char :=
    match check_N_isValidChar (N_of_Nat n) as isValid
          return check_N_isValidChar (N_of_Nat n) = isValid -> Char with
    | true => fun H => Char_ofNatAux n (Nat_isValidChar_of_check_N n H)
    | false => fun _ => Char_ofNatAux 0 Nat_isValidChar_zero
    end Logic.eq_refl.
=======
  Definition Char_legacy_mk_N
    (val : N)
    (isLt : ((val <? 0x100000000)%N && check_N_isValidChar val)%bool = true)
    : Char_legacy :=
    Char_legacy_mk
      (UInt32_legacy_mk_N val (proj1 (andb_prop _ _ isLt)))
      (Nat_isValidChar_mk_N val (proj2 (andb_prop _ _ isLt))).
>>>>>>> parent of dec4a1b (Predeclare modern Char construction helpers)

  Definition reflective_Char_mk (val : N)
    : if ((val <? 0x100000000)%N && check_N_isValidChar val)%bool
      then Char
      else InvalidChar val
    := let isLt := ((val <? 0x100000000)%N && check_N_isValidChar val)%bool in
       match isLt return ((val <? 0x100000000)%N && check_N_isValidChar val)%bool = isLt -> if isLt then Char else InvalidChar val with
       | true => fun H => Char_mk_N val H
       | false => fun _ => invalid_char val
       end Logic.eq_refl.

  Definition reflective_Char_mk_prim (val : Uint63.int)
    := reflective_Char_mk (Z.to_N (Uint63.to_Z val)).


  (* Definition reflective_UInt32_mk (val : N) : if (val <? 0x100000000)%N
                                              then UInt32
                                              else InvalidUInt32 val
    := let isLt := (val <? 0x100000000)%N in
       match isLt return (val <? 0x100000000)%N = isLt -> if isLt then UInt32 else InvalidUInt32 val with
       | true => fun H => UInt32_mk_N val H
       | false => fun _ => invalid_uint32 val
       end Logic.eq_refl.

  Definition reflective_UInt32_mk_prim (val : Uint63.int)
    := reflective_UInt32_mk (Z.to_N (Uint63.to_Z val)).


  Definition check_isValidChar (n : Nat) : bool
    := let n := N_of_Nat n in
        ((n <? 0xd800) || ((0xdfff <? n) && (n <? 0x110000)))%N%bool.

  Definition reflective_isValidChar_mk (n : Nat)
    : if check_isValidChar n
      then n < 0xd800 \/ (0xdfff < n /\ n < 0x110000)
      else InvalidChar n.
  Proof.
    cbv [check_isValidChar].
    pose proof (Nat_lt_to_N_l n 0xd800) as H1.
    pose proof (Nat_lt_to_N_r 0xdfff n) as H2.
    pose proof (Nat_lt_to_N_l n 0x110000) as H3.
    destruct N.ltb; cbn [orb];
    [ | destruct N.ltb; cbn [andb]; [ | constructor ] ];
    [ | destruct N.ltb; cbn [andb]; [ | constructor ] ];
    [ apply Or_inl, nat_le_Nat_le; revert H1 | apply Or_inr, And_intro; apply nat_le_Nat_le; [ revert H2 | revert H3 ] ];
    clear.
    all: cbv [Nat_of_N Nat_of_num_uint].
    all: intro H; specialize (H Logic.eq_refl).
    all: apply Nat_le_nat_le' in H.
    1: etransitivity; [ exact H | ].
    2: etransitivity; [ | exact H ].
    3: etransitivity; [ exact H | ].
    all: clear.
    all: zify; clear.
    all: cbn [nat_of_Nat]; rewrite ?nat2Natid, ?Nat2Z.inj_succ, ?N_nat_Z.
    all: vm_compute; congruence.
  Qed.
  End with_or. *)


End strings.

Register UInt8_toNat as lean.UInt8_toNat.
Register UInt8_toUInt32 as lean.UInt8_toUInt32.
Register Nat_isValidChar as lean.Nat_isValidChar.
Register Char as lean.Char.
Register reflective_Char_mk_prim as lean.Char.mk.reflective_prim.

Goal forall a n, Nat_pow a (Nat_succ n) = Nat_mul (Nat_pow a n) a.
Proof.
  intros. simpl. reflexivity.
Abort.
