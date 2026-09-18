# PR #70: controlled CSLib comparison

On 2026-09-08, removing #70's universe-instance changes caused **no import
regression in the CSLib prefix and original dependency exports tested here**.
Both full-export attempts stopped at the same kernel-conversion timeout.
This establishes neither a full CSLib pass nor that #70 can never be useful.

## Comparison

Both importers start from `integration/importer-review-experimental` at
`68fe7e6589c9266941c99d5e9503e902f9f6e6fc`. The kernel and all other importer
fixes are held fixed: experimental Rocq `22cc1ac2`, matching Stdlib `3e47b26f`.

The “without” variant restores the PR parent's declaration contexts and
implicit source-prefix/extra-level representation, including Eq, quotients,
ULift and recursors. Direct-level tracking is retained solely for the later,
independent nested-container lower-bound policy; it no longer prunes universe
parameters. This is an adapted inverse of #70, not an unmodified git revert
across the later overlapping patches. See the
[complete source delta](../work/pr70-cslib-ablation/without-pr70.patch).

Both foundations and imports are freshly compiled in isolated worktrees.
No saved CSLib prefix, substituted library proof, or changed kernel is used
to distinguish the variants. Exact commits and input hashes are in
[provenance.json](../work/pr70-cslib-ablation/provenance.json).

| Test | With #70 | Without #70 |
| --- | --- | --- |
| Complete 81,106-line core fixture | Pass, 112.13 s | Pass, 113.84 s |
| Original `Int64.toInt_minValue` proof and dependencies | Pass | Pass |
| Original CSLib FinLoop totality proof and dependencies | Pass | Pass |
| CSLib `FreeM.bind_assoc` and `FreeM.foldFreeM_unique` | Pass | Pass |
| `Lean.Meta.DiscrTree.Trie.casesOn` and `Lean.Meta.DiscrTree.casesOn` | Pass | Pass |
| Mutual Prop/SProp instances, nested containers, mutual nested recursors | Pass | Pass |
| Full CSLib export attempt | Timeout at line 697,462, 251.05 s | Same timeout, 251.58 s |
| PR's explicit `UniverseBox@{a b}` assertion | Pass | Fails: two universes supplied, four expected |

The core and earlier reduced Int64 fixtures use Lean 4.29. The full CSLib
export, FinLoop, FreeM and the tested discrimination-tree export use the
actual CSLib Lean 4.27.0-rc1 toolchain, CSLib commit `02e2a23e`. FreeM and
DiscrTree were freshly exported from the original compiled declarations;
their commands and hashes are in
[target-exports.json](../work/pr70-cslib-ablation/target-exports.json).
The saved Lean 4.29 `DiscrTree.lean-export` was prepared but not used in the
final tests; those use `DiscrTree427.lean-export`.

## Full-export limit

The input is the identical 22,828,731-line `cslib-hints.lean-export`, SHA-256
`ce6fb77ab3905e0dbbc9668dad42f3cbfee474c131b472140cc4da94f8b323ae`.
Both runs use error mode `Fail`, a 20-second declaration timeout, a 600-second
process timeout, the same 3 GiB guard and no swap. There are no skipped-error
messages, and the 5,818 declaration/field announcements are identical up to
the failure. These announcements include fields and are not a theorem count.

Both fail with:

```text
Error at line 697462 (for _private.Init.Data.String.Decode0.String.toBitVec_getElem_utf8EncodeChar_zero_of_utf8Size_eq_two): #HINT_OPAQUE 37553 654522 654686
Lean import line timed out.
```

The stack traces are in kernel conversion. This is the previously investigated
[UTF-8 bitvector conversion problem](../work/utf8-bitvec-two-repro/README.md),
not a reported missing-universe-constraint error. No conclusion is drawn about
the remaining full-export declarations. The targeted exports provide additional
coverage independent of that early blocker; they are not a replacement for
checking the rest of the entire input.

## Interpretation

The explicit `UniverseBox` assertion is a control: it confirms that the
ablation restores #70's observable interface difference. Its Lean fixture
imports successfully in both variants; only the Rocq assertion about exposed
universe parameters fails without #70.

There is therefore still no demonstrated CSLib import failure fixed by #70.
The historical Int64 constraint error remains attributable to `4de13e2` in
the retired proof-reconstruction path, as established in the
[earlier reproduction](pr70-universe-reproduction.md). This comparison adds
direct tests of the original proofs with the current importer fixes held fixed.

## Logs and reproduction

- [Without: core, Int64, FinLoop](../work/pr70-cslib-ablation/without-core-fixed/result.json)
- [With: same cases and full CSLib attempt](../work/pr70-cslib-ablation/with-comparison-01/result.json)
- [Without: full CSLib attempt](../work/pr70-cslib-ablation/without-comparison-01/result.json)
- [Full-prefix comparison](../work/pr70-cslib-ablation/full-prefix-comparison.json)
- [Without: original FreeM/DiscrTree and mutual/nested fixtures](../work/pr70-cslib-ablation/without-targets-01/result.json)
- [With: the same focused tests](../work/pr70-cslib-ablation/with-targets-01/result.json)
- [Without: interface control](../work/pr70-cslib-ablation/without-interface-control/result.json)
- [With: interface control](../work/pr70-cslib-ablation/with-interface-control/result.json)

Each result file records the exact commands, toolchain, stages and exit codes.
The worktrees are `_worktrees/review/pr70-cslib-with` and
`_worktrees/review/pr70-cslib-without`. Import test files and the exported inputs
are preserved. Re-run the recorded validation command with a new output
directory, respecting the shared single-worker guard.

An initial trial build failed on an accidental redundant OCaml local open;
it was corrected before any import ran. One attempted launch was refused
because another workload owned the guard. The first focused export hit its
2 GiB aggregate RSS limit; it completed with a 4 GiB export-only limit.
The Rocq import limits remain identical between variants. These setup events
are retained in the evidence directory and are not counted as import failures.
No PR or branch was changed during this investigation.
