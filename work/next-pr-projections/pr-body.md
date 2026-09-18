Title: Fix dependent projection types and relevance

Importing a recursive record with a proof field fails at `DepRec.proof` with
an illegal application error. Importing `Subtype` specialized to `Prop`
also fails: the generated case expression is marked relevant when its
result must be irrelevant. Both errors occur during `Lean Import`, before
the tests' explicit type assertions.

When constructing case-based projections, substitute the preceding
projections into later field types and derive the result relevance from
the projected field's type in the correct binder context. This preserves
dependent field types and handles the SProp specialization.

The change is based directly on upstream `c8db093` and does not include or
require PR #70. It reuses the projection fix from `submit/dependent-projections`.

Validation on unmodified upstream Rocq `56acfe11` with matching compiled
Stdlib:

- Both regression imports fail on the upstream base and pass with this change.
- Exact projection and dependent-recursor type assertions pass.
- Existing `rec_single_ctor.v` and `ulift.v` tests pass.

This validates the reduced examples; it does not claim a complete CSLib check
or resolution of the historical `Int64.toInt_minValue` error.
