From LeanImport Require Import Lean.
Require Import CheckpointIndexedMutualBase.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/mutual_instances" 149 180.
Check polyPropExample : PolyTree_inst1 True.
Check PolyTree_inst1.
Check PolyForest_inst1.
Fail Definition indexed_mutual_prop_wrong : nat := polyPropExample.
