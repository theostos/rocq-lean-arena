From LeanImport Require Import Lean.
Set Lean Error Mode "Fail".
Unset Lean Skip Missing Quotient.
Set Lean Line Timeout 30.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/universe_instances".
Universe a b.
Constraint Set < a.
Constraint a < b.
Check UniverseBox@{a b} : Type@{a} -> Type@{b}.
Check universeValueType : UniverseBox_inst1 Nat.
Fail Check (universeValueType : nat).
