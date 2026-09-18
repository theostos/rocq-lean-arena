From LeanImport Require Import Lean.
Require Import CslibTo5084182.

Set Kernel Conversion Dep Heuristic.

Fail Definition foldl_cons_does_not_reduce
    (A B : Type)
    (f : A -> B -> A)
    (init : A)
    (head : B)
    (tail : CslibTo1000000.List_inst1 B) :
  CslibTo1000000.List_foldl_inst3 A B f init
    (CslibTo1000000.List_cons_inst1 B head tail) =
  CslibTo1000000.List_foldl_inst3 A B f (f init head) tail.
  := eq_refl _.

Example foldl_cons_reduces_after_unfolding
    (A B : Type)
    (f : A -> B -> A)
    (init : A)
    (head : B)
    (tail : CslibTo1000000.List_inst1 B) :
  CslibTo1000000.List_foldl_inst3 A B f init
    (CslibTo1000000.List_cons_inst1 B head tail) =
  CslibTo1000000.List_foldl_inst3 A B f (f init head) tail.
Proof.
  unfold CslibTo1000000.List_foldl_inst3,
    CslibTo1000000.List_brecOn_inst2,
    CslibTo1000000.List_brecOn_go_inst2,
    CslibTo1000000.List_foldl_match_1_inst5.
  exact (eq_refl _).
Qed.
