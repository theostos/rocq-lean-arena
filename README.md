# Rocq Lean Typechecker Arena

Small experiment: run Lean Kernel Arena exports through
[`rocq-lean-import`](https://github.com/rocq-community/rocq-lean-import), then let
Rocq check the result.

Pipeline:

```text
Lean Kernel Arena NDJSON -> legacy lean-export -> rocq-lean-import -> Rocq
```

## Setup

Create the opam switch used for these runs.

This uses the latest development version by pinning
`rocq-community/rocq-lean-import` to upstream `master` (require Rocq 9.3+).

## Bootstrap

Fetch Lean Kernel Arena and install this checker into it:

```sh
make bootstrap
make build-checker
```

The arena is pinned by [scripts/bootstrap_arena.sh](scripts/bootstrap_arena.sh).

## Tutorial

Build and run all tutorial cases:

```sh
make build-test TEST=tutorial
make run TEST='tutorial/*'
```

The results are produced with `rocq-lean-import` pinned to upstream `master`.
See [docs/tutorial-gaps.md](docs/tutorial-gaps.md) for notes from the local
investigation.

Current result with upstream `rocq-lean-import`:

```text
correct:   125 / 133
incorrect:   8 / 133
```

## Mathlib

Build the full mathlib export:

```sh
make build-test TEST=mathlib
```

Run the checker:

```sh
make run TEST=mathlib
```

This is large. The first run creates:

```text
_deps/lean-kernel-arena/_build/tests/mathlib.ndjson
_deps/lean-kernel-arena/_build/tests/mathlib.lean-export
```

The `.lean-export` file is cached and reused by later runs.

Known first failure:

```text
UInt32.toBitVec
```

For the first observed failure, see
[docs/mathlib-root-repros.md](docs/mathlib-root-repros.md).

## Variables

Keep going after errors for diagnostics:

```sh
ROCQLKA_LEAN_ERROR_MODE=Skip make run TEST=mathlib
```

Keep the generated temporary `Check.v`:

```sh
ROCQLKA_KEEP_TMP=1 make run TEST=mathlib
```
