# Augmented simplex singleton-type reduction repair — 2026-09-18

Production stopped at NDJSON line **50,115,358**,
`AugmentedSimplexCategory.tensorObj_hom_ext`, in the 50M–55M chunk.
The 50M checkpoint had already been serialized, sealed and successfully reloaded.
This was a conversion failure, not memory exhaustion or a timeout.

## Cause and repair

The failing branch has two arrows `f g` from `tensorObj star star` to `of z`.
Their common arrow type reduces to a fieldless singleton, so `eq_refl f` also
has the required type `eq f g`. The singleton classifier used beta/iota/zeta
reduction plus head-alias unfolding. It could not unfold a transparent definition
*inside the discriminant of a type-level match*, and rejected the resulting
blocked case stack before obtaining the singleton type.

The pre-fix worker also rejects this tiny closed example at `Qed`:

```coq
Inductive U := unit_value.
Register U as kernel.unit_like.
Definition bool_alias (b : bool) := b.
Definition family (b : bool) : Type := if b then U else nat.
Goal forall f g : family (bool_alias true), f = g.
Proof. intros f g. exact_no_check (eq_refl f). Qed.
```

In the export's pinned Lean kernel, `is_def_eq_unit_like` first takes
`whnf(infer_type(t))`, checks that the resulting inductive has a single fieldless
constructor, and compares that complete type with the other operand's type:
[pinned Lean type_checker.cpp](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp#L977).

`kernel/conversion.ml` now uses the same transparency-respecting full type-head
reduction policy for singleton classification as for the existing final type
witness. `unit_type_reduction_infos` factors that policy out of
`unit_type_after_stack`. This allows delta reduction inside matches/projections
and structural fixpoints, using the ordinary closure reducer.

Unchanged safety conditions:

- Classification is still an isolated private closure query with its existing
  shared 4096-work allowance; no limits were raised.
- Both caller transparency and the conversion oracle restrict unfolding.
- Classification alone cannot accept equality: the complete relocated operand
  types are still compared by conversion.
- Relevant, neutral and opaque negative cases still fail kernel checking.
- No reduction rule, registration rule, serialized representation, proof body,
  importer source, timeout or production memory policy was weakened.

## Focused evidence

`prepare.py` extracts the exact theorem and its complete dependency closure:
145,416 NDJSON records, **zero abstracted dependency proofs**. It converts the
same records to the existing diagnostic legacy stream (145,412 lines). Hashes
and the exact target range are in `slice.json`.

- `baseline-unit/`: the small example fails on the old production worker.
- `baseline-prefix/`: all dependency proofs compile on the old worker (80s
  harness wall time, including checkpoint serialization).
- `baseline-target/`: the extracted theorem reproduces the production failure
  on the twelfth matcher argument.
- `candidate-unit/`: computed discriminants, nested matches, structural
  recursion, primitive projections, parameterized singleton types, record eta,
  and opaque/neutral/non-unit controls pass on the repaired worker.
- `candidate-target/`: the exact theorem passes (10s harness wall time, including
  startup and serialization; approximately 0.962s for its final kernel declaration).
- `candidate-target/independent.json`: `rocqchk` passes the target artifact
  (37 declarations, 1.62s checker elapsed time). This uses `-norec`: it rechecks
  the target artifact, reusing the separately compiled dependency prefix,
  foundation and stdlib. It is **not** a fresh independent check of all Mathlib.

Worker: `ed7e25350e150a2d2eca568d98975473e091930e9c053ae23dcd99c70eeab1d3`.
Checker: `d456eb8235bad335d1c00ef289787f6c15478b3060068d5a8b2e13760972708c`.
ABI-rebuilt importer: `work/kernel-alignment-pass/importer.OJ3rkMcY`, unchanged
source from `importer.q64CBLVp`, including the previous constructor-context fix.
`conversion-baseline.ml` and `rocqworker-baseline.exe` preserve the prior state.

The full regression suite was explicitly waived. No full Mathlib success is claimed.

## Continuation

`resume.py release` binds the successful evidence and repaired worker to a new
consumer certificate and starts `rocq-mathlib-simplex-25gb.service` from the
sealed **50,000,001** cursor. It reuses the already-tested runtime memory adapter:
25 decimal GB maximum, 2 GiB host reserve, no swap. The historical plan and all
producer seals stay unchanged, with 5M-line checkpoints and 1800s/declaration.
The loop verifies the checkpoint chain and reloads 50M before importing again.

Progress: `work/mathlib-alignment-5m-20260913-with-terminal/latest/`.
Startup confirmation only; no ongoing assistant monitoring.
