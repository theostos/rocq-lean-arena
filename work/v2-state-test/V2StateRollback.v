From LeanImport Require Import Lean.
Require Import V2StatePart1.

Set Lean Error Mode "Fail".

(* The impossible upper bound fails after reaching EOF.  Rocq must roll back
   both the live importer state and the queued V2 snapshot. *)
Fail Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/universe_instances" 62 74.

Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/universe_instances" 62 67.
Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/compact-peano-importer-current/dumps/universe_instances" 67 73.

Check universeValueType : UniverseBox_inst1 Nat.
