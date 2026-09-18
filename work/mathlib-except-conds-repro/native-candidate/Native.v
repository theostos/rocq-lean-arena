Set Kernel Conversion Dep Heuristic.
Inductive U := unit_value.
Register U as kernel.unit_like.
Inductive Shape := pure | arg (s : Shape) | except (s : Shape).
Fixpoint Conds (s : Shape) : Type :=
  match s with pure => U | arg t => Conds t | except t => (bool * Conds t)%type end.
Fixpoint combine (s : Shape) : Conds s -> Conds s -> Conds s :=
  match s return Conds s -> Conds s -> Conds s with
  | pure => fun _ _ => unit_value
  | arg t => combine t
  | except t => fun p q => (andb (fst p) (fst q), combine t (snd p) (snd q))
  end.
Goal forall p q : Conds pure, p = combine pure p q.
Proof. intros p q. exact_no_check (eq_refl p). Qed.
Goal forall p q : Conds pure, p = q.
Proof. intros p q. exact_no_check (eq_refl p). Qed.
