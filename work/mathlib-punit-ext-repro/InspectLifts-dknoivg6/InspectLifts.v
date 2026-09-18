Require Import MathlibTo13000000.
Print MathlibTo1000000.ULift_inst2.
Print MathlibTo1000000.PLift_inst1.
Print MathlibTo1000000.ULift_up_inst2.
Print MathlibTo1000000.PLift_up_inst1.

Set Kernel Conversion Dep Heuristic.
Definition wrapped_proofs (P : SProp)
    (x y : MathlibTo1000000.ULift_inst2 (MathlibTo1000000.PLift_inst1 P)) :
    Lean.eq x y := Lean.eq_refl x.
