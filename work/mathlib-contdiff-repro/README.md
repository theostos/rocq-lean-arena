# ContDiffAt.real_of_complex timeout

Mathlib 8a178386ffc0f5fef0b77738bb5449d50efeea95, Lean 4.29.0.
The full run timed out at line 4,855,902 after 600 seconds.
`IsometryEquiv_inst3.toEquiv20` was an incidental on-demand declaration.

## Original-export diagnostic

```sh
python3 work/mathlib-contdiff-repro/faithful.py
```

Checks the original full export through line 4,855,901, saves `ContDiffPrefix.vo`,
then loads it and traces only `ContDiffAt.real_of_complex`. No proof abstraction
or lazy instantiation. The first prefix build takes time; repeating the command
reuses it only while the export, binaries, foundation and standard library match.
Prefix creation is atomic and its inputs and artifact are hash-checked.

After the runner prints its log path, monitor in another terminal:

```sh
tail -n 5 -F work/mathlib-contdiff-repro/faithful/latest/*.log
```

One worker, 8 GiB memory budget, 3 GiB system reserve, no swap; 600 seconds per
declaration and an eight-hour outer limit per compilation. `--memory-mib 16384`
selects the full-run budget if enough memory is available. No automatic repairs.
Neither mode continues past the target. Kernel and importer are not rebuilt.

A checkpoint reload changes the module context and clears process-local caches.
If the target passes, it is **not** a reproduction of the original timeout. Use
the single-import control to preserve the original prefix-checking history:

```sh
python3 work/mathlib-contdiff-repro/faithful.py --from-start
```

This checks lines 1 through 4,855,902 in one import, with diagnostics enabled.
`--dry-run` prints the plan without launching or creating files. No full-size
run of this new runner has been performed yet.

## Dependency-only attempts

`Target.lean-export` contains the unchanged theorem and its dependencies:
2,717,559 lines, SHA256 `5a6fc1f8d890b71cc07553d4fab750ba1b19802befb63e02c3ced60eda02095e`.
The exporter selected `ContDiffAt.real_of_complex` from
`Mathlib.Analysis.Complex.RealDeriv` using the reference Mathlib build.

```sh
python3 work/mathlib-contdiff-repro/run.py NEW-TAG --trace --line-timeout 600
```

Use a unique lowercase tag. The runner compiles a fresh foundation, checks from
line 1, and records binary/export hashes. Limits: one worker, 4 GiB, no swap,
3 GiB system reserve, 900-second total deadline. No checkpoints or retries.
An outer status 124 is not a declaration-checking failure.

`baseline` was cancelled to enable diagnostics. `focused-baseline` tried lazy
dependency instantiation and hit an independent stale universe-graph error at
`IsOrderedAddMonoid`: a cached `Lean.Set+3.0` was missing from the local graph.
This mode is not used in `traced-baseline`, which matches the full run's settings.

No importer or kernel fix has been made for this timeout yet. Conversion entry
and declaration-phase diagnostics are in `traced-baseline/Full.run.log`.

## Diagnostic minimization

`traced-baseline` hit its outer 900-second limit at `closure_minimal`, before
the target. It did not reproduce the reported declaration timeout.

`slice.py` computes a dependency slice after replacing selected **Lean theorem**
bodies with axioms of their original types. Computational definitions and the
target proof remain unchanged. Literal-construction dependencies are retained.
These inputs are diagnostic controls, not library-validation results.

- `sliced-literals`: 137,902 lines; passes, including the target (0.37s in quickdef).
- `sliced-direct`: restores the four direct lemma proofs; also passes.
- `sliced-calculus`: restores `ContDiff*`, `contDiff*` and the linear-map
  smoothness proofs; 178,258 lines, also passes.
- `sliced-isometry-path`: retains the proof path through composition,
  `HasFTaylorSeriesUpToOn.hasFDerivWithinAt`, and `IsometryEquiv.continuous`.
  This also passes: 235,745 lines, 218.6s total CPU, with the target's final
  quickdef check taking 0.47s. Peak cgroup memory was 763,004 KiB.

No small failing reproduction has been confirmed by the above passing controls.
The full Mathlib export, importer and kernel have not been modified.
