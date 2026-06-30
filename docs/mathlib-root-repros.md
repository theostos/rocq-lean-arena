# Mathlib First Failure

This note only records the first failure seen when running:

```sh
make run TEST=mathlib
```

The full mathlib run is large. After the cache exists, rerun only the small
prefix around the first failure with:

```sh
head -n 1304 \
  _deps/lean-kernel-arena/_build/tests/mathlib.lean-export \
  > /tmp/uint32-toBitVec.lean-export

ROCQLKA_OPAM_SWITCH=rocq93_dev \
  checkers/rocq-lean-import/scripts/run.sh \
  /tmp/uint32-toBitVec.lean-export
```

## Error

```text
Error at line 1304 (for UInt32.toBitVec): #DEF 237 998 1000
The term "fun self : UInt32 => val0 self" has type
 "UInt32 -> Fin UInt32_size"
while it is expected to have type
 "UInt32 -> BitVec (OfNat_ofNat_inst1 Nat 32 (instOfNatNat 32))".
```

## Meaning

`rocq-lean-import` predefines `UInt32` as a record containing a `Fin UInt32_size`.
Lean 4.29 exports `UInt32.toBitVec` with type `UInt32 -> BitVec 32`.

So the first mathlib failure is a mismatch between the importer's built-in
model of `UInt32` and the `UInt32` exported by current Lean.
