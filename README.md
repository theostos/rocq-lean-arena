# Rocq Lean Typechecker Arena

Small experiment: run Lean Kernel Arena exports through
[`rocq-lean-import`](https://github.com/rocq-community/rocq-lean-import), then let
Rocq check the result.

Pipeline:

```text
Lean Kernel Arena NDJSON -> legacy lean-export -> rocq-lean-import -> Rocq
```

## Setup

The reference environment is a clean `rocq93_clean` opam switch. Exact Rocq,
stdlib, and importer-base commits are recorded in
[`config/rocq-lean-import.lock.json`](config/rocq-lean-import.lock.json).

```sh
scripts/setup_rocq93_clean.sh
```

Development runs load both the Rocq library and plugin from the selected local
importer worktree. This avoids accidentally combining an installed plugin with
locally built `.vo` files.

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

The results below were produced with the original upstream importer baseline.
See [docs/tutorial-gaps.md](docs/tutorial-gaps.md) for notes from the local
investigation.

Current result with upstream `rocq-lean-import` master
(`38fb4791bc7a3bc49995526448778c6e5555aaf1`):

```text
correct:   129 / 133
incorrect:   4 / 133
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

## Cslib frontier

Run one reproducible first-failure experiment with the canonical generic
integration branch:

```sh
scripts/run_rocq_frontier.py \
  _deps/lean-kernel-arena/_build/tests/cslib.lean-export
```

The runner builds the selected importer worktree, verifies the importer commit
and Rocq version, records time and memory, and writes the current frontier to
`_build/frontier/state.json`.

Use `--from-line` and `--until-line` together to check a bounded export range.

## Variables

Keep going after errors for diagnostics:

```sh
ROCQLKA_LEAN_ERROR_MODE=Skip make run TEST=mathlib
```

Override the canonical local importer or clean Rocq switch with:

```sh
make run \
  ROCQLKA_OPAM_SWITCH=rocq93_clean \
  ROCQLKA_IMPORTER_ROOT=/path/to/rocq-lean-import
```

Each run keeps a temporary checker directory by default and prints its path.
It contains the generated `Check.v`, converter logs, and Rocq stdout/stderr.

Use a different location for these directories:

```sh
ROCQLKA_TMP_ROOT=/tmp/rocq-lean-runs make run TEST=mathlib
```

Remove the temporary directory automatically:

```sh
ROCQLKA_KEEP_TMP=0 make run TEST=mathlib
```
