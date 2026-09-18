# PR #70: recovered CSLib error and attribution

Follow-up: [controlled CSLib comparison with #70 removed](pr70-cslib-comparison.md).
Both variants reach the same kernel timeout and pass the selected original
CSLib/dependency proofs; no import regression was found in that coverage.

Investigation on 2026-09-08 for [Gaetan's question](https://github.com/rocq-community/rocq-lean-import/pull/70#issuecomment-5582961233)
on [Translated universe instances, #70](https://github.com/rocq-community/rocq-lean-import/pull/70).

The old CSLib error is recoverable and reproducible. However, the claim in
the PR body and the earlier stack handoff that #70 fixes this particular
error is misattributed. The historical failure occurs in the old
declaration-specific proof-reconstruction implementation, which already
contains the complete translated universe-instance representation.

## Original error

The saved full-CSLib log is
`_deps/lean-kernel-arena/_build/reports/cslib-except-eta-full`, lines
13521–13526, dated 2026-07-10 19:10 +02:00:

```text
Error at line 1288568 (for Int64.toInt_minValue): #DEF 79935 1197132 1197133
Universe constraints are not implied by the ones declared:
Lean.Set+1.0 <= eq_sind_r.u0
Lean.Set+1.0 <= eq_ind_r.u0
```

An excerpt is preserved in
[historical-cslib-error.log](../work/pr70-universe-repro/historical-cslib-error.log).
The full export used Lean 4.27.0-rc1 and CSLib
`02e2a23eef42925cc87a5ce2ec76e9d07fdee267`.

## Fresh reproduction

All builds and imports use `rocq93_clean`: Rocq 9.3+rc1, OCaml 4.14.2,
with both the plugin and `.vo` files loaded from the selected isolated
importer checkout. They run sequentially under the existing 3 GiB memory
guard, with no swap and a 15 GiB system reserve. Imports have a 60-second
timeout.

The saved dependency export
[Int64.lean-export](../work/pr70-universe-repro/Int64.lean-export) has 9,225
lines (182,666 bytes). It was generated with Lean 4.29.0 from:

```lean
def int64MinValueRepro : Int64.minValue.toInt = -2^63 :=
  Int64.toInt_minValue
```

This is a smaller, separately generated export; its declaration IDs and
line numbers differ from the original full CSLib export.

On historical commit `ba22a2d21f89d57d6d02e062d5d2f026fb7d337d`, it fails
at line 9,222 with the **same two constraints**. See
[int64-historical-before.log](../work/pr70-universe-repro/int64-historical-before.log).

The identical export **passes** on the immediate successor `4de13e2`,
including the final `Check Int64_toInt_minValue`. See the full
[after log](../work/pr70-universe-repro/run-historical-after-int64.G1KOHdfE/result.log)
and its saved exit status of 0. Neither input nor toolchain changes between
these two runs.

The next commit, `4de13e203338e424980d055f8a6d38dcd57eeb41`, is titled
`Preserve monomorphic reconstructed proofs`. Its only source change is in
`declare_reconstructed_def`: use a monomorphic declaration when the
translated universe context is empty, and permit additional constraints
in the remaining polymorphic case. Previously the reconstruction path
always used a polymorphic declaration with a non-extensible universe
context; the tactic-generated proof introduced the constraints above.

The failing historical checkout already has `uconv.direct`, `direct_pairs`,
`decl_pairs`, and complete instance recipes in `instantiation.algs`. That
representation was present in `5856ee5`, before this July 10 failure. The
reconstruction function is absent from both the parent and head of #70.

## What #70's own regression establishes

Comparing the exact PR parent `38fb4791bc7a3bc49995526448778c6e5555aaf1`
with its head `2dc7529e2c9a9f999d944ae8495474a6503246df`:

| Check | Parent | PR head |
| --- | --- | --- |
| Import the PR's `universe_instances` fixture | Succeeds | Succeeds |
| Assert `UniverseBox@{a b} : Type@{a} -> Type@{b}` | Fails: instance length 2, expected 4 | Passes |
| Import the reduced `Int64` export | 60-second timeout at `Int64.toInt_minValue` | Same 60-second timeout |

Logs: [parent](../work/pr70-universe-repro/universes-before.log),
[PR head](../work/pr70-universe-repro/universes-after.log).
The `Int64` timeout logs are [parent](../work/pr70-universe-repro/int64-before.log)
and [PR head](../work/pr70-universe-repro/run-after-int64.wAEcdmkp/result.log).
These bounded runs establish neither successful checking nor an eventual
universe error for `Int64` on the standalone PR branches.

The fixture has:

```lean
universe u v
axiom UniverseBox (α : Type u) : Type (max (u + 1) v)
axiom universeValue (α : Type u) : UniverseBox.{u, v} α
noncomputable def universeValueType : UniverseBox.{0, 1} Nat := universeValue Nat
```

The old representation retains the original source universes as well as
the synthesized successor/maximum levels, giving four Rocq parameters.
The PR exposes the two levels used by the translated type. The failing
check is an explicit assertion about that representation, **not an import
failure of this Lean fixture**.

## Commands and artifacts

From the arena repository root:

```sh
bash work/pr70-universe-repro/run.sh before universes
bash work/pr70-universe-repro/run.sh after universes
bash work/pr70-universe-repro/run.sh historical-before int64
bash work/pr70-universe-repro/run.sh historical-after int64
```

The script checks the selected commit, builds through the resource guard,
and retains separate logs and exit statuses for each invocation. Expected
failures return nonzero. Commit IDs, input hashes, original-log hash,
toolchain information, and resource settings are in
[provenance.json](../work/pr70-universe-repro/provenance.json).

No existing development checkout was reset, and no GitHub comment or PR
edit was posted.
