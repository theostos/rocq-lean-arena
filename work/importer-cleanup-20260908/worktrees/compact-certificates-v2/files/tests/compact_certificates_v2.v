From Stdlib Require Import NArith.
From LeanImport Require Import Lean.

Open Scope N_scope.

Definition fixedVarWitness : N := 100000000%N.
Definition fixedVar : Nat := CompactNat fixedVarWitness.

Example certificate_1000 :
  NatCertificateV2 (CompactNat 1000%N) 1000%N.
Proof. exact (NatCertificateV2_of_N 1000%N). Qed.

Example certificate_10000 :
  NatCertificateV2 (CompactNat 10000%N) 10000%N.
Proof. exact (NatCertificateV2_of_N 10000%N). Qed.

Example certificate_100000 :
  NatCertificateV2 (CompactNat 100000%N) 100000%N.
Proof. exact (NatCertificateV2_of_N 100000%N). Qed.

Example certificate_1000000 :
  NatCertificateV2 (CompactNat 1000000%N) 1000000%N.
Proof. exact (NatCertificateV2_of_N 1000000%N). Qed.

Example certificate_10000000 :
  NatCertificateV2 (CompactNat 10000000%N) 10000000%N.
Proof. exact (NatCertificateV2_of_N 10000000%N). Qed.

Example certificate_100000000 :
  NatCertificateV2 (CompactNat 100000000%N) 100000000%N.
Proof. exact (NatCertificateV2_of_N 100000000%N). Qed.

Example fixedVar_certificate :
  NatCertificateV2 fixedVar fixedVarWitness.
Proof. exact (NatCertificateV2_of_N fixedVarWitness). Qed.

Example fixedVar_literal_equality :
  eq fixedVar (CompactNat 100000000%N).
Proof.
  apply (NatCertificateV2_equal _ _ 100000000%N).
  - exact fixedVar_certificate.
  - exact (NatCertificateV2_of_N 100000000%N).
Qed.

Example fixedVar_comparison_certificate :
  BoolCertificate
    (Nat_beq fixedVar (CompactNat 100000000%N)) true.
Proof.
  change
    (BoolCertificate
       (Nat_beq fixedVar (CompactNat 100000000%N))
       (N.eqb 100000000 100000000)).
  apply NatCertificateV2_beq_bool.
  - exact fixedVar_certificate.
  - exact (NatCertificateV2_of_N 100000000%N).
Qed.

Example fixedVar_comparison_is_true :
  eq (Nat_beq fixedVar (CompactNat 100000000%N)) Bool_true.
Proof.
  apply (BoolCertificate_equal _ _ true).
  - exact fixedVar_comparison_certificate.
  - exact (BoolCertificate_of_bool true).
Qed.

(* A wrong binary witness leaves an impossible compact [N] equality. *)
Fail Definition corrupted_fixedVar_equality :
  eq (CompactNat 100000000%N) (CompactNat 100000001%N) :=
  NatCertificateV2_equal_witnesses
    (CompactNat 100000000%N) (CompactNat 100000001%N)
    100000000%N 100000001%N
    (NatCertificateV2_of_N 100000000%N)
    (NatCertificateV2_of_N 100000001%N)
    (Logic.eq_refl 100000000%N).
