From LeanImport Require Import Lean.
Require Import V2StatePart1.

Set Lean Error Mode "Fail".

(* This entry depends on names and expressions persisted by [V2StatePart1]. *)
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/universe_instances" 62 67.

Universe a b.
Constraint Set < a.
Constraint a < b.

Check UniverseBox@{a b} : Type@{a} -> Type@{b}.
Check universeValue.
