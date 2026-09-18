From LeanImport Require Import Lean.

Lean Import "/home/theo/Documents/github/rocq-lean-typechecker/_worktrees/rocq-lean-import/distributed-import/dumps/nested_record_containers".

Check recordTreeSize : RecordTree -> Nat.
Check recordListSize : List_inst1 (Payload RecordTree) -> Nat.
Check recordPayloadSize : Payload RecordTree -> Nat.
Check nestedRecordExample : Nat.

Example nestedRecordExample_computes : nestedRecordExample = 10.
Proof. cbv. reflexivity. Qed.
