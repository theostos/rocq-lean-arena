From LeanImport Require Import Lean.
Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Unset Lean Just Parsing.
Unset Lean Lazy Instantiation.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/work/finloop-repro/NullaryUnit.ndjson" 1 980.
Check choose_eq.
Check chooseDep_eq.
Check unitMatch_eq.
Check unbox_eq.
Fail Definition wrong_bit : bitValue Bit_off = bitValue Bit_on := eq_refl _.
Fail Definition wrong_box : unbox (Box_mk (Nat_succ Nat_zero)) = Nat_zero := eq_refl _.
