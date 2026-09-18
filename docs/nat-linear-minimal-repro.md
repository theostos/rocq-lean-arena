# Minimal Timeout Repro

The timeout can be reproduced with no explicit Lean import.

Primary file:

```text
_deps/lean-kernel-arena/tests/repros/no-import-list-pair-simple-timeout-short.lean
```

The whole example is:

```lean
abbrev Data := List Nat

opaque Good : Data → Data → Prop

def expensiveSplit : Nat → Data → Data → Data × Data
  | 0, left, right => (left, right)
  | _ + 1, [], right => ([], right)
  | fuel + 1, _ :: left, right => expensiveSplit fuel left right

def largeFuel := 10000000

def transform (left right : Data) : Data × Data :=
  expensiveSplit largeFuel left right

structure Box where
  left : Data
  right : Data

abbrev Box.good (box : Box) : Prop :=
  Good box.left box.right

def wrap (box : Box) : Box :=
  let (left, right) := transform box.left box.right
  { left, right }

axiom transform_preserves_good (left right : Data) :
  Good (transform left right).fst (transform left right).snd = Good left right

theorem explicit (left right : Data) :
    Good (transform left right).fst (transform left right).snd = Good left right := by
  exact transform_preserves_good left right

theorem repro (left right : Data) :
    (wrap { left, right }).good = Box.good { left, right } := by
  simp [Box.good, wrap]
  exact Iff.of_eq (transform_preserves_good left right)
```

## Result

The direct theorem passes:

```text
explicit
```

The wrapper theorem times out:

```text
line 1255: repro
Timed out after 60 seconds without rocq stdout progress.
```

The direct theorem proves the final proposition explicitly:

```lean
Good (transform left right).fst (transform left right).snd = Good left right
```

The failing theorem writes the same idea through the wrapper:

```lean
(wrap { left, right }).good = Box.good { left, right }
```

Lean simplifies the wrapper theorem to the explicit shape, but Rocq gets stuck
checking that proof.

## Reproduce

Build:

```sh
cd _deps/lean-kernel-arena
PATH="/home/theo/Documents/github/rocq-lean-typechecker/scripts/no-perf:$PATH" \
  python3 lka.py build-test 'repros/no-import-list-pair-simple-timeout-short'
```

Run:

```sh
cd /home/theo/Documents/github/rocq-lean-typechecker
ROCQLKA_OPAM_SWITCH=rocq93_dev \
ROCQLKA_PROGRESS_TIMEOUT=60 \
checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/tests/repros/no-import-list-pair-simple-timeout-short.ndjson
```

Control:

```sh
cd _deps/lean-kernel-arena
PATH="/home/theo/Documents/github/rocq-lean-typechecker/scripts/no-perf:$PATH" \
  python3 lka.py build-test 'repros/no-import-list-pair-simple-timeout-short-explicit'
```

```sh
cd /home/theo/Documents/github/rocq-lean-typechecker
ROCQLKA_OPAM_SWITCH=rocq93_dev \
checkers/rocq-lean-import/scripts/run.sh \
  _deps/lean-kernel-arena/_build/tests/repros/no-import-list-pair-simple-timeout-short-explicit.ndjson
```

## Bottleneck Shape

The failing shape appears to need:

- a transparent recursive function over symbolic data;
- a pair result;
- a wrapper that stores the pair projections into two separate structure fields;
- a proof that transports through that wrapper unfolding.

Related smaller shapes pass locally:

```text
NoImportListSingleWrapperTimeout.repro
NoImportOneFieldPairTimeout.repro
NoImportPairWrapperTimeout.repro
```

Fuel note: in earlier scans, `largeFuel := 10000` passed, while
`largeFuel := 100000` already timed out. The current file uses `10000000` to
make the timeout robust.

## Lean-Core Counterpart

The closest version using Lean core's real `Poly.cancel` is:

```text
_deps/lean-kernel-arena/tests/repros/polycnstr-cancel-only-minimal-timeout.lean
```

It also times out:

```text
line 22324: Nat.Linear.PolyCnstrCancelOnlyMinimalTimeout.repro
Timed out after 120 seconds without rocq stdout progress.
```
