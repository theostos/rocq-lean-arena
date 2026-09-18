Set Kernel Conversion Dep Heuristic.

Inductive PNat := PZero | PSucc : PNat -> PNat.
Register PNat as kernel.ind_peano_nat.
Fixpoint double n :=
  match n with PZero => PZero | PSucc k => PSucc (PSucc (double k)) end.
Register double as kernel.peano_nat_double.

Inductive ProofArg : SProp := proof_a | proof_b.
Definition ProofTail (_ : PNat) := ProofArg -> nat.
Fixpoint choose (n : PNat) (x : nat) {struct n} : ProofTail n :=
  match n with
  | PZero => fun _ => 0
  | PSucc k => fun proof => choose k x proof
  end.

Goal choose (PSucc PZero) 0 proof_a = choose (PSucc PZero) 1 proof_b.
Proof. exact_no_check (eq_refl (choose (PSucc PZero) 0 proof_a)). Timeout 5 Qed.

Goal choose (double (PSucc PZero)) 0 proof_a =
     choose (double (PSucc PZero)) 1 proof_b.
Proof.
  exact_no_check (eq_refl (choose (double (PSucc PZero)) 0 proof_a)).
  Timeout 5 Qed.

Record Tagged := tag { number : nat; valid : ProofArg }.
Fixpoint ignore_tag (n : PNat) (value : Tagged) : nat :=
  match n with PZero => 0 | PSucc k => ignore_tag k value end.

Goal ignore_tag (PSucc PZero) (tag 0 proof_a) =
     ignore_tag (PSucc PZero) (tag 1 proof_b).
Proof.
  exact_no_check (eq_refl (ignore_tag (PSucc PZero) (tag 0 proof_a))).
  Timeout 5 Qed.

Fixpoint ignore_tag_prefix (n : PNat) (value : Tagged) (last : nat) : nat :=
  match n with PZero => last | PSucc k => ignore_tag_prefix k value last end.

Goal ignore_tag_prefix (PSucc PZero) (tag 0 proof_a) 7 =
     ignore_tag_prefix (PSucc PZero) (tag 1 proof_b) 7.
Proof.
  exact_no_check (eq_refl (ignore_tag_prefix (PSucc PZero) (tag 0 proof_a) 7)).
  Timeout 5 Qed.
