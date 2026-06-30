# Mathlib Root Error Reproducers

These reproducers are small prefixes of the cached mathlib legacy export:

```text
_deps/lean-kernel-arena/_build/tests/mathlib.lean-export
```

The generated repro files are in:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/
```

They use the same `rocq-lean-import` path as the normal checker. Later errors
need `Set Lean Error Mode "Skip"` because `UInt32.toBitVec` is the first hard
failure and otherwise stops the run before later independent failures.

## `UInt32.toBitVec`

Reproducer:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/uint32-toBitVec-prefix.lean-export
```

Run:

```sh
ROCQLKA_OPAM_SWITCH=rocq93_dev \
  checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/repros/mathlib-root-causes/uint32-toBitVec-prefix.lean-export
```

Full error:

```text
Error at line 1304 (for UInt32.toBitVec): #DEF 237 998 1000
The term "fun self : UInt32 => val0 self" has type
 "UInt32 -> Fin UInt32_size"
while it is expected to have type
 "UInt32 -> BitVec (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))".
```

Raw output:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/uint32-toBitVec.stdout
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/uint32-toBitVec.stderr
```

## Projection From Non-Record: `Trans`

Reproducer:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/trans-projection-prefix.lean-export
```

Run:

```sh
ROCQLKA_OPAM_SWITCH=rocq93_dev \
ROCQLKA_LEAN_ERROR_MODE=Skip \
  checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/repros/mathlib-root-causes/trans-projection-prefix.lean-export
```

Full error:

```text
Skipping: Error at line 75873 (for Function.LeftInverse.eq_rightInverse): #DEF 7768 66631 66820 12 79
cannot project non record Trans
```

Raw output:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/trans-projection.stdout
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/trans-projection.stderr
```

## Projection From Non-Record: `Inhabited`

Reproducer:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/inhabited-projection-prefix.lean-export
```

Run:

```sh
ROCQLKA_OPAM_SWITCH=rocq93_dev \
ROCQLKA_LEAN_ERROR_MODE=Skip \
  checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/repros/mathlib-root-causes/inhabited-projection-prefix.lean-export
```

Full error:

```text
Skipping: Error at line 95020 (for ite_eq_left_iff): #DEF 9523 83890 84044 12
cannot project non record Inhabited
```

Raw output:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/inhabited-projection.stdout
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/inhabited-projection.stderr
```

The `PLift` projection failures are later, after the long
`Nat.Linear.ExprCnstr.denote_toNormPoly` entry. They are visible in the partial
full-pass log, but they are not as clean as standalone prefix repros without an
interactive interrupt of that earlier slow entry.

## Stack Overflow

Reproducer:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/isValidChar-stack-prefix.lean-export
```

Run:

```sh
ROCQLKA_OPAM_SWITCH=rocq93_dev \
ROCQLKA_LEAN_ERROR_MODE=Skip \
  checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/repros/mathlib-root-causes/isValidChar-stack-prefix.lean-export
```

Full error:

```text
Skipping: Error at line 10350 (for _private.Init.Prelude0.isValidChar_UInt32.match_1_1): #DEF 1746 8264 8300
Stack overflow.
```

Raw output:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/isValidChar-stack.stdout
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/isValidChar-stack.stderr
```

The later `UInt64.ofNatLT` stack overflow has the same error class, but it is
past the slow `Nat.Linear.ExprCnstr.denote_toNormPoly` entry and is therefore
less convenient as a standalone prefix repro.

## Slow Entry / Manual Interrupt

This is not a logical Rocq rejection. It reproduces the long-checking entry by
running the prefix and interrupting it with `timeout`.

Reproducer:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/denote-toNormPoly-timeout-prefix.lean-export
```

Run:

```sh
timeout -k 5s -s INT 45s \
  env ROCQLKA_OPAM_SWITCH=rocq93_dev \
      ROCQLKA_LEAN_ERROR_MODE=Skip \
  checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/repros/mathlib-root-causes/denote-toNormPoly-timeout-prefix.lean-export
```

Full error after the interrupt:

```text
Skipping: Error at line 376778 (for Nat.Linear.ExprCnstr.denote_toNormPoly): #DEF 29921 341599 341972
User interrupt.
```

Raw output:

```text
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/denote-toNormPoly-timeout.stdout
_deps/lean-kernel-arena/_build/repros/mathlib-root-causes/denote-toNormPoly-timeout.stderr
```
