From LeanImport Require Import Lean.
Require Import CslibTo3808374.

Lemma imported_unit_eta (x y : CslibTo1000000.Unit) :
  @Logic.eq CslibTo1000000.Unit x y.
Proof. exact (@Logic.eq_refl CslibTo1000000.Unit x). Qed.

Section DependentResult.
  Universe u.
  Variable A : Type@{u}.
  Variable beq : CslibTo1000000.BEq A.
  Variable a : A.
  Variable l l' :
    CslibTo1000000.List
      (CslibTo1000000.Sigma_inst2 A
        (fun _ : A => CslibTo1000000.Unit)).
  Variable h :
    @eq Bool
      (CslibTo2500000.Std_Internal_List_containsKey_inst2 A
        (fun _ : A => CslibTo1000000.Unit) beq a l)
      Bool_true.
  Variable h' :
    @eq Bool
      (CslibTo2500000.Std_Internal_List_containsKey_inst2 A
        (fun _ : A => CslibTo1000000.Unit) beq a l')
      Bool_true.

  Lemma dependent_imported_unit_eta :
    @Logic.eq CslibTo1000000.Unit
      (CslibTo2500000.Std_Internal_List_getValue_inst2
        A CslibTo1000000.Unit beq a l h)
      (CslibTo2500000.Std_Internal_List_getValue_inst2
        A CslibTo1000000.Unit beq a l' h').
  Proof.
    exact (@Logic.eq_refl CslibTo1000000.Unit
      (CslibTo2500000.Std_Internal_List_getValue_inst2
        A CslibTo1000000.Unit beq a l h)).
  Qed.
End DependentResult.
