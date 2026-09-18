I recovered the original CSLib log and reproduced the same error on the old
experimental importer branch:

```text
Error at line 1288568 (for Int64.toInt_minValue): #DEF 79935 1197132 1197133
Universe constraints are not implied by the ones declared:
Lean.Set+1.0 <= eq_sind_r.u0
Lean.Set+1.0 <= eq_ind_r.u0
```

However, I had misattributed it in the PR description. This error came from
the old tactic-based reconstruction of `Int64.toInt_minValue`, whose proof
was saved with a non-extensible polymorphic universe context. The failing
historical revision (`ba22a2d`) already contained the complete
universe-instance representation proposed here.

With the same reduced export and Rocq 9.3+rc1, `ba22a2d` reproduces both
missing constraints, while its immediate successor `4de13e2` (`Preserve
monomorphic reconstructed proofs`) passes.

The regression I can independently demonstrate for this PR is the
`UniverseBox` example in `tests/universe_instances.v`: on the parent
(`38fb479`), the import itself succeeds, but the check
`UniverseBox@{a b} : Type@{a} -> Type@{b}` fails with
`Universe instance length for UniverseBox is 2 but should be 4.`
It passes at the PR head (`2dc7529`). So the claim about fixing the above
CSLib error should be removed from this PR's description.
