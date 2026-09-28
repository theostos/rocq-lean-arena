# Rocq Lean Typechecker Arena

**Mathlib reproduction: [short quickstart](QUICKSTART.md).** The September 2026
scoped export passes with zero admissions; use the pinned experimental branches
in that guide. The workflows below describe earlier experiments.

Small experiment: run Lean Kernel Arena exports through
[`rocq-lean-import`](https://github.com/rocq-community/rocq-lean-import), then let
Rocq check the result.

For developers: the [cslib review map](docs/review-map.md) links each importer,
kernel and runner change to its branch, topic diff and validation status.

Current cslib workflow: [manual checking from line 1](docs/cslib-manual-method.md).
Autonomous repair is disabled; new full runs do not reuse checkpoints.
The user starts and monitors each run.

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

For the Arena Lean 4.29 reference with the current experimental Rocq kernel:

```sh
python3 scripts/run_mathlib_from_start.py
```

This reuses the existing reference NDJSON, converts it with reducibility hints
if needed, and checks from line 1 without checkpoints or automatic repairs.
See the [manual Mathlib guide](docs/mathlib-manual-method.md) for logs and resource
limits. The commands below describe the older Arena checker configuration,
not the experimental kernel used for cslib.

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

Each new history entry records its own freshly computed input SHA-256 and the
selected Rocq command (`ROCQLKA_ROCQ`, or `rocq`) used for both the version probe
and compilation. Separate runs keep separate logs. Command/version metadata
does not identify a clean upstream kernel build or all loaded artifacts;
reloading experimental checkpoints with a stock executable is not a fresh
upstream-kernel verification.

Use `--from-line` and `--until-line` together to check a bounded export range.
The frontier runner forces fail-on-error checking and takes its range only from
these command-line arguments. Missing quotients, reported errors, or skipped
entries cannot produce a successful frontier result.

The cslib experiment uses a **modified experimental kernel**, not the reference
switch above. Its current workflow is [manual checking from line 1](docs/cslib-manual-method.md),
without checkpoint reuse or model-driven retries. The former
[cslib loop](scripts/cslib-loop/README.md) and
[Mathlib queue](scripts/mathlib-loop/README.md) are disabled; their guides and
[older notes](work/cslib-v2/README.md) are historical. This does not yet establish
a successful full cslib or Mathlib check.

## Resource safety

The checker `build.sh` and `run.sh` entry points, and the frontier runner's
build/version checks, use one user-wide memory guard. Run commands sequentially;
parallel build jobs are rejected. A second guarded task or an existing unguarded
Rocq worker prevents launch.

This requires Linux, cgroup v2, and a working user systemd manager with delegated
memory controls. If protection cannot be established, the command refuses to
start. Defaults are a **3 GiB hard limit**, **no swap**, and a **15 GiB system
reserve**. Admission requires the full budget plus the reserve to be available;
the guard also stops the workload if available memory falls to the reserve.

Limits are configurable in KiB, for example:

```sh
ROCQ_MAX_RSS_KIB=4194304 \
ROCQ_MIN_AVAILABLE_KIB=14155776 \
  scripts/run_rocq_frontier.py path/to/input.lean-export
```

This permits at most 4 GiB while reserving 13.5 GiB; it does not request that
other applications release memory. Keep the reserve appropriate for your other
work. Full settings are listed at the top of
[run-memory-guarded.sh](checkers/rocq-lean-import/scripts/run-memory-guarded.sh).
Do not invoke the `*-internal.sh` implementations directly. Setup, Lean export
generation (`make build-test`), and manually launched tools are outside this
guard; these limits apply to the Rocq checker workflow.

Resource-safety dispatch and cancellation tests use mocks only:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_rocq_resource_safety.py'
```

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

### v9 survey-mode pre-validation results (`data/prevalidate-dev9`, 600 s theorem cutoff)

- 20M-40M: complete, 0 new timeouts (2.6 h). 80M-100M: complete, 0 new timeouts (2.7 h).
- 60M-80M: 1 timeout (`pseudofunctor._proof_7`, fixed in v10+), otherwise clean to 80M.
- 40M-60M: kernel anomaly at 53,910,405 (fixed in v11+); the 53.9M-60M tail is re-validated with v12
  (`data/prevalidate-dev12`, worker from 40M).
So, on v9, the only issues found across 20M-100M were the two already repaired; v12 carries both
repairs plus the review fixes.
