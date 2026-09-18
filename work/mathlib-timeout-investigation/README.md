# Investigate the representation-theory timeout

Target: `Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq` (NDJSON line 9,239,031).

See [FINDINGS.md](FINDINGS.md) for the subsequent inspection, isolated patch,
regressions and the faster checked-prefix reproduction. The description below
is the original baseline diagnostic; its launcher refuses a changed worker.

This extends the dependency-cache measurement to conversion, allocation/GC,
and kernel checking. It reuses the same worker, 9M checkpoint, module name,
input interval, proof bodies and 1,800-second line timeout. It enables existing
diagnostic flags and Rocq's built-in profiler; no source changes or rebuilds.

The launcher waits for the previous measurement's lock, then performs one
16 GiB guarded replay. It never starts the full Mathlib loop. GDB launches its
own child (no privileged attachment); the sampler requests a stack every
20 seconds during the target and validates the worker's tracer before signaling.
Conversion-entry logs outside the target are discarded. No conversion-pair
retention table is enabled.

```sh
bash work/mathlib-timeout-investigation/start.sh
tail -n 10 -F work/mathlib-timeout-investigation/latest/run.log
```

Python waits for the process, then writes `latest/REPORT.md`. This report
summarizes recorded numbers and stacks; it does not reason about the cause.
`invocation.json` records the inputs and commands. `kernel-profile.json` is
Rocq's native profile, including conversion subtimes and allocation counts.
`investigation.json` preserves target phases, compared heads, and native stacks.

The cache-only run is the lower-instrumentation baseline. The broader run's
logging/profiling and debugger pauses affect timing; samples are not precise
CPU fractions. Identifying and testing the cause is a separate analysis step.
