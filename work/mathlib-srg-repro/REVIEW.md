# SimpleGraph.IsSRGWith constructor-context fix

Failure: original Mathlib record 42,181,159, while generating the imported
induction scheme. The last printed field (`card`) is not the precise failing
field analysis: the diagnostic identifies an equality over common-neighbour
cardinality.

`lean_scheme.packet_recinfo` took the constructor fields out of `mind_nf_lc`
and called `has_rec_hyp` on every field type in the global environment. These
types are open under the constructor parameters and earlier fields. Nested
uniform-parameter eta expansion can perform real reduction, including case
inversion, and therefore needs that context even for non-recursive fields.

Evidence: `baseline-diag/run.log` reproduces the production stack, and reports
an environment of depth 4 for a term containing `Rel 15` (`scoped=false`).
No exception was suppressed. The kernel's relative-variable lookup is correct
to require a corresponding environment entry.

Fix in `_worktrees/rocq-lean-import/cslib-ndjson/src/lean.ml`: instantiate the
complete constructor context at the scheme's universe instance, push the
parameters, then analyse fields outermost-to-innermost, pushing each field
after its type has been analysed. Accumulating results by cons preserves the
previous innermost-first flag order used for recursor reordering. Parameter
let-definitions are retained. The existing no-field-let invariant is unchanged.

Validation completed:

- Proof-preserving slice: 61,342 NDJSON records, zero abstracted proofs.
- Before fix: exact exception reproduced in 30.17 seconds.
- After fix: complete slice compiled in 35.17 seconds (including launcher
  polling/serialization); `candidate-slice/result.json` records the artifact.
- Independent checker: all slice declarations/proofs rechecked in 4.55 seconds,
  reusing only foundation/stdlib (`-norec`, not a strict-profile run).
- A 1,265-line miniature (`ConstructorScope.lean`) also reproduces the old
  importer's failure. Candidate miniature and broader regressions were not run
  because the user explicitly requested skipping further regression work.

The Rocq worker and checker binaries, checking flags, declaration timeout and
memory limits are unchanged. The new consumer certificate authorizes exactly
the reviewed `src/lean.ml` digest change; all other importer sources must match
the producer. Producer artifacts and checkpoint seals are not rewritten.

Resume: from the sealed 40M checkpoint, next input record 40,000,001. Checkpoints
remain every 5M records, with the existing 16 GiB/no-swap guard and 3 GiB reserve.
Full Mathlib verification is not yet complete. See `resume.log`,
`resume-approval.json` and the production generation's `progress.json`.
