From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/mutual_instances" 1 149.
Check PolyTree.
Check PolyForest.
Fail Check PolyTree_inst1.
Fail Check PolyForest_inst1.
Fail Definition indexed_mutual_wrong : nat := PolyTree.
