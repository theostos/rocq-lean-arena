# Dependency-cache measurement

Target: `Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq`.

- Exit status: **1**.
- Target interval: **1796.04 CPU seconds**.
- All dependency queries: **53.701–54.089 CPU seconds**, at most **3.012%** of the target interval.
- Cache construction (included above): **6.189–6.577 CPU seconds**, at most **0.366%** of the target interval.

`build_cpu` includes nested misses only once; it is a subset of `query_cpu`.
Construction includes both newly demanded entries and entries rebuilt after reload; it bounds the latter's cost.
Interrupted queries/builds are counted before the exception propagates.
Bounds account for the one-CPU-second snapshot interval and rounded declaration timestamps.
For a timeout, the interval ends at process exit and includes error-reporting cleanup.

These are instrumented CPU measurements, not wall time or a cache-memory measurement.
Timing/counter overhead can slow this replay; no full cache-on/cache-off speedup is inferred.
The replay preserves the 9M checkpoint, intervening input, module name and proof bodies.
