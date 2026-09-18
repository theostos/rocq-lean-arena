# Offline scheduling study for the complete CSLib certificate

This directory accompanies the [parallel-import design](../../docs/parallel-import-design.md).
It contains a tested scheduling model and a full-input structural experiment.
**It does not run Rocq, implement parallel importing, or measure proof-checking
speedup.** No importer, kernel, runner, or memory-guard code was modified.

## Scope and data

The input is the original Arena CSLib certificate with SHA-256
`cb677997476de3e79ce08b061757334d0777a8f1d8ec0d34da6a5f345a7f3483`:
253,649 importer entries, 262,983 named constants, and 21,039,124 expression
nodes. This study retains all entries, including the imported library environment.

The graph comes from the earlier
[validated overlap study](../cslib-module-overlap-20260909/README.md).
Its Lean metadata supplies direct references and recorded module ownership for
the original certificate's constants. It is **offline analysis data**;
the production design extracts dependencies directly from Arena's input and
requires neither Lean source files nor compiled Lean modules.

There are 4,894,019 direct edges and 253,619 strongly connected components,
including 3,614 nontrivial components; the largest has 103 named constants.
No component crosses a recorded module boundary. These are structural units,
not a proof that every cycle is a supported mutual declaration. A production
importer must validate that separately and account for generated Rocq instances.

## Four-worker structural comparison

All policies preserve the same total work under each proxy. The scheduler uses
longest remaining dependent path first and releases a task only when all its
prerequisites complete. There is no mandatory previous-chunk edge.

| Policy | Tasks | Entry-count proxy speedup | Entry + introduced-expression proxy speedup |
|---|---:|---:|---:|
| Individual graph components | 253,619 | 4.000x | 4.000x |
| File ownership, cyclic groups merged | 3,207 | 3.775x | 3.904x |
| Consecutive topological chunks, about 256 entries | 991 | 1.586x | 1.486x |
| Independent batches, capacity 32 entries | 8,011 | 3.997x | 3.986x |
| Independent batches, capacity 128 entries | 2,071 | 3.902x | 3.796x |
| Independent batches, capacity 512 entries | 586 | 2.919x | 2.706x |

The raw [simulation.json](simulation.json) also includes 2-, 8-, and 16-worker
simulations and critical-path bounds. More simulated workers do not represent
additional physical cores on the current four-core laptop.

These results support investigating moderate dependency-aware batches:
chronological chunks introduce long dependencies even without explicitly
chaining every chunk, while very small tasks expose more graph width at the
cost of many artifacts. The table does **not** determine the fastest real batch
size. A production batch cost includes launching, loading dependencies,
translation, kernel checking, and saving.

## Why raw file ownership needs correction

The 3,228 recorded source modules produce two cyclic groups when their
declarations are grouped into one task per module. Merging each cyclic group
gives the 3,207-task comparison above. The cycles and witness declarations are
included in `simulation.json`.

One two-module cycle involves
`Init.Data.Iterators.Lemmas.Combinators.Take` and
`Std.Data.Iterators.Lemmas.Combinators.TakeWhile`: a generated
`Std.Iterators.Iter.atIdxSlow?._unary.induct_unfolding` declaration attributed
to the former references a generated private theorem attributed to the latter,
which also depends on declarations attributed to the former.

The other involves 21 Init modules. In particular the dependency collector
assigns a string-literal dependency from `Lean.Name.hasMacroScopes`, attributed
to `Init.Prelude`, to `String.ofList` in `Init.Data.String.Bootstrap`.
Dependencies from the latter return toward the prelude.

These are cycles in the **coarsened certificate-dependency model**, not a claim
that Lean's source import graph is cyclic. Implicit literal dependencies and
generated declarations make recorded file ownership insufficient as a standalone
compilation plan. The recommended production plan checks its actual graph and
uses smaller batches when necessary.

## Model assumptions

* The first proxy gives each importer entry one work unit; constructors and
  recursors remain within their families. Every policy totals 253,649 units.
* The second adds each expression node once, charged to the first declaration
  that introduces it in the original export order. It totals 21,292,773 units.
  This is a data-allocation proxy, not expression traversal cost or kernel time;
  shared expressions can participate in expensive checks many times.
* Atomic components are indivisible. Antichain batching groups components of
  equal dependency depth, with exact prerequisite edges and no whole-layer
  barriers. A larger-than-capacity component stays intact.
* The model has zero startup, parsing, serialization, artifact-loading, final-join,
  communication, and retry cost. It does not model dynamically generated
  universe specializations or changed conversion behavior.
* Each task reserves one abstract memory unit. The scheduler supports other
  supplied reservations and backfilling, but this experiment has no actual RSS
  estimates. Coarsening resets reservations to one unit per batch.

Consequently these are optimistic **graph-only** speedups. The design's 2–3x
end-to-end target on the laptop remains unverified. Per-instance kernel timings
and dependency-environment memory measurements are needed to estimate it.

## Reproduction and validation

From the repository root:

```bash
python3 -m unittest discover \
  -s work/distributed-import-design-20260909 -p 'test_*.py' -v

prlimit --as=1073741824 --cpu=180 /usr/bin/time -v \
  python3 work/distributed-import-design-20260909/analyze_full_graph.py \
  > work/distributed-import-design-20260909/analysis.log 2>&1
```

The eight tests cover dependency ordering, a known diamond makespan, memory
admission/backfilling, impossible reservations, zero-cost dependency chains,
invalid graphs, cycle-producing coarsenings, source-order preservation,
component boundaries, and work preservation under batching.

The full experiment checks all original counts, input-cache consistency,
dependency coverage, component membership, and acyclicity of each simulated
plan. Every schedule checks complete execution and the work/critical-path
lower bounds. See `analysis.log` for the successful run and resource usage.
The analysis process is capped at 1 GiB address space and 180 seconds of CPU;
it never launches a compiler or proof-checker subprocess.

`parsed.pickle` in the earlier study is our own local cache. It must not be
replaced by an untrusted pickle. To use a different certificate, regenerate the
earlier study and deliberately update this pinned experiment's coverage checks.

Files: [scheduler_model.py](scheduler_model.py),
[analyze_full_graph.py](analyze_full_graph.py),
[test_scheduler_model.py](test_scheduler_model.py),
[simulation.json](simulation.json), and [provenance.json](provenance.json).
