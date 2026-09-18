# PR #70: fresh CSLib comparison

Investigation completed. See [the results and limits](../../docs/pr70-cslib-comparison.md).
No import regression was found without #70 in the tested cases. Both full-export
attempts stop at the same line-697462 kernel timeout; full CSLib is unverified.

The two isolated importers start from integration `68fe7e6`. The kernel is
experimental runtime `22cc1ac2`, with matching Stdlib `3e47b26f`. The `without`
variant restores #70's parent universe construction and prefix/extra instance
representation. Its complete source delta is `without-pr70.patch`.
The later nested-container lower-bound policy is retained; direct-level
tracking remains only to support that policy and no longer prunes declaration
parameters. Eq, quotient, ULift and recursor instances use the old convention.

Both foundations and imports are compiled afresh. No existing compiled CSLib
prefix is reused. No kernel, library proof, other importer algorithm or saved
checkpoint is modified. Runtime, PR and input hashes are in `provenance.json`.

Initial results without #70 (`without-core-fixed/result.json`):

- Complete 81,106-line core fixture: pass.
- Original `Int64.toInt_minValue` dependency export: pass (237 entries).
- Original CSLib FinLoop totality proof: pass.

The same three tests also pass with #70 in `with-comparison-01/result.json`.
The raw CSLib comparison uses the identical 22,828,731-line `cslib-hints`
export, failure mode `Fail`, a 20-second declaration timeout and a 600-second
process limit. These bounds must be reported if they stop the comparison.

`run-comparison.py` waits for the existing single-worker resource guard,
then runs the two variants sequentially. Results are recorded separately.
A failed trial build in `without-core` records an accidental redundant
`Summary.Ref` local open; this was corrected before any import ran.
`with-cslib` records resource-guard admission refusal while another validation
owned the scope. Neither is an importer regression result.

The additional `DiscrTree.lean-export` is a dependency export of the original
Lean discrimination-tree recursors used by CSLib. It was converted from the
saved Lean 4.29 export; it is distinct from the full CSLib export's Lean 4.27
version. The earlier Int64 reduced export likewise uses Lean 4.29; the FinLoop
export uses the original CSLib Lean 4.27 toolchain.
