# `Nat.Linear.ExprCnstr.denote_toNormPoly` diagnostic

This checks whether the recurrent timeout is caused by the environment before
the theorem, by the theorem type, or by the theorem body.

## Source declaration

Lean source:

```text
_deps/lean4-src/src/Init/Data/Nat/Linear.lean:480
```

The Lean source theorem is small, but it is elaborated into a proof term using
`simp`, `rw`, and the preceding polynomial cancellation lemmas:

- `Nat.Linear.Poly.denote_eq_cancel_eq`
- `Nat.Linear.Poly.denote_le_cancel_eq`

## Repro files

The test uses the regenerated `cslib.lean-export`, because it already uses
`#DEF` for theorem proofs.

Target declaration:

```text
_deps/lean-kernel-arena/_build/tests/cslib.lean-export:499590
#DEF 30475 464745 465103
```

The name id is:

```text
_deps/lean-kernel-arena/_build/tests/cslib.lean-export:499200
30475 #NS 29676 denote_toNormPoly
```

Generated repros:

```text
_deps/lean-kernel-arena/_build/repros/denote-toNormPoly-diagnostic/cslib-before.lean-export
_deps/lean-kernel-arena/_build/repros/denote-toNormPoly-diagnostic/cslib-with-def.lean-export
_deps/lean-kernel-arena/_build/repros/denote-toNormPoly-diagnostic/cslib-with-ax.lean-export
```

The axiom variant changes only the last line:

```text
#DEF 30475 464745 465103
```

to:

```text
#AX 30475 464745
```

## Results

Run with:

```sh
ROCQLKA_OPAM_SWITCH=rocq93_dev \
ROCQLKA_PROGRESS_TIMEOUT=180 \
checkers/rocq-lean-import/scripts/run.sh <file>
```

Results:

```text
cslib-before.lean-export   passes,  elapsed 1:10, maxrss 1496952KB
cslib-with-ax.lean-export  passes,  elapsed 1:25, maxrss 1505904KB
cslib-with-def.lean-export timeout, elapsed 4:22, maxrss 1406964KB
```

The timeout run stops at:

```text
line 499590: Nat.Linear.ExprCnstr.denote_toNormPoly
Timed out after 180 seconds without rocq stdout progress.
```

## Conclusion

The environment before the theorem is valid: `cslib-before` passes.

The theorem type is also acceptable to Rocq: `cslib-with-ax` passes.

The problem is therefore the proof body `465103`. Rocq gets stuck while
checking the imported proof term for `Nat.Linear.ExprCnstr.denote_toNormPoly`.
This is a kernel/importer performance problem around conversion/checking of the
elaborated Lean proof term, not an NDJSON conversion issue and not a malformed
`UInt32`/`UInt64` predeclaration.

The theorem block itself adds only 391 export lines, so the slowdown is not just
because the declaration is syntactically huge. The likely trigger is reduction
through the proof dependencies, especially the preceding `Poly.cancel` semantic
lemmas used by the `simp`/`rw` proof.
