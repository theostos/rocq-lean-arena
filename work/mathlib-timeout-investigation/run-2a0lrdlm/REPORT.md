# Timeout investigation

Target: `Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq`.

Intentionally interrupted after 120.598 target CPU seconds to collect diagnostics; this replay did not exhaust its configured 1800-second timeout. The separate full-duration baseline did.

This is an automatically generated evidence summary, not an automatic diagnosis.

## Declaration phases

- start → before type: 0.000 CPU seconds.
- before type → after type: 0.002 CPU seconds.
- after type → before body: 0.000 CPU seconds.
- before body → after body: 0.215 CPU seconds.
- after body → before universes: 0.001 CPU seconds.
- before universes → after universes: 0.019 CPU seconds.
- after universes → before quickdef: 0.001 CPU seconds.
- before quickdef → after name: 0.000 CPU seconds.

## Conversion

Retained 1186 top-level conversion entries during the target (thinned after 10,000; final entry retained).
Last recorded entry: call **33744**, CPU timestamp 1337.352.

`typed=true relevance=false projection=false dependency=true LeanImport.Lean.eq.<ind>/3 <> LeanImport.Lean.eq.<ind>/3`

An entry names the top-level compared heads, not every recursive comparison. Without an exit marker, it alone does not prove which call owned the timeout.

## Kernel checking and allocation

Longest `Typeops.execute` events across this replay (wall time, including debugger pauses):
- 710.724 s; conversion subtimes: 711s 695ms, 608 calls; minor allocation: 2.85E+10 w; major allocation: 1.66E+09 w; major/minor collections: 15/6809.
- 149.568 s; conversion subtimes: 150s 554ms, 232 calls; minor allocation: 5.87E+09 w; major allocation: 3.42E+08 w; major/minor collections: 3/1402.
- 145.620 s; conversion subtimes: 146s 592ms, 528 calls; minor allocation: 5.88E+09 w; major allocation: 3.42E+08 w; major/minor collections: 3/1404.

## Native stacks

Captured 7 stacks; recorded stop overhead: 0.081 seconds (excludes signal-delivery/resume overhead).
These are sparse wall-clock samples, not exact CPU percentages.
- 2 samples: `#0  camlNames__equal_3098 () at kernel/names.ml:515`
- 1 samples: `#0  0x0000621405ac62d2 in bf_allocate (wosz=2) at freelist.c:1513`
- 1 samples: `#0  caml_oldify_one (v=127188630515672, p=p@entry=0x73acaad1f018) at minor_gc.c:200`
- 1 samples: `#0  0x000062140588701d in camlCClosure__append_stack_2114 () at kernel/cClosure.ml:420`
- 1 samples: `#0  __getrusage (who=who@entry=RUSAGE_SELF, usage=usage@entry=0x7ffc124b2740) at ../sysdeps/unix/sysv/linux/getrusage.c:29`
- 1 samples: `#0  0x000062140588746d in camlCClosure__lft_fconstr_2138 () at kernel/cClosure.ml:458`

## Dependency-cache timings

Target: `Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq`.

- Exit status: **1**.
- Target interval: **121.22 CPU seconds**.
- All dependency queries: **8.906–9.712 CPU seconds**, at most **8.012%** of the target interval.
- Cache construction (included above): **5.361–6.167 CPU seconds**, at most **5.088%** of the target interval.

`build_cpu` includes nested misses only once; it is a subset of `query_cpu`.
Construction includes both newly demanded entries and entries rebuilt after reload; it bounds the latter's cost.
Interrupted queries/builds are counted before the exception propagates.
Bounds account for the one-CPU-second snapshot interval and rounded declaration timestamps.
For a timeout, the interval ends at process exit and includes error-reporting cleanup.

These are instrumented CPU measurements, not wall time or a cache-memory measurement.
Timing/counter overhead can slow this replay; no full cache-on/cache-off speedup is inferred.
The replay preserves the 9M checkpoint, intervening input, module name and proof bodies.

## Interpretation still required

Use the conversion call/head, full stacks, kernel subtimes, and cache timings together to locate the expensive comparison. Then test any proposed cause with a focused reproduction or a one-factor comparison. Logging/profiling overhead means this replay is not an uninstrumented speed benchmark. No proofs, conversion policy or checkpoints were changed.
