From LeanImport Require Import Lean.
Require Import V2StatePart1 V2StatePart2.

Set Lean Error Mode "Fail".

(* The final definition depends on the entry persisted by [V2StatePart2]. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/universe_instances" 67 73.

Universe a b.
Constraint Set < a.
Constraint a < b.

Check UniverseBox@{a b} : Type@{a} -> Type@{b}.
Check universeValueType : UniverseBox_inst1 Nat.
