Set Kernel Conversion Dep Heuristic.
Inductive PNat := PZero | PSucc : PNat -> PNat.
Register PNat as kernel.ind_peano_nat.
Inductive ProofArg : SProp := proof_a | proof_b.
Definition proof_id (proof : ProofArg) : ProofArg := proof.
Record Tagged := tag { number : nat; valid : ProofArg }.
Fixpoint ignore_tag_prefix (n : PNat) (value : Tagged) (last : nat) : nat :=
  match n with PZero => last | PSucc k => ignore_tag_prefix k value last end.
Goal ignore_tag_prefix (PSucc PZero) (tag 0 (proof_id proof_a)) 7 =
     ignore_tag_prefix (PSucc PZero) (tag 1 (proof_id proof_b)) 8.
Proof.
  exact_no_check (eq_refl (ignore_tag_prefix (PSucc PZero) (tag 0 (proof_id proof_a)) 7)).
  Timeout 5 Qed.
