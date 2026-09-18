# Mathlib: 1,000 entries, eight workers followed by one

Both runs succeeded and saved `aggregate/All.vo`. Their exact original-entry
coverage and specialization-provider sets match; final artifact hashes were
verified. These are cold batch runs on the same certificate prefix, not a
comparison against the monolithic importer.

| Worker limit | End-to-end wall time | Peak cgroup memory | Maximum live workers | Entries | Attempts |
|---:|---:|---:|---:|---:|---:|
| 8 | 13m 30s | 0.661 GiB | 2 | 1000 | 437 |
| 1 | 14m 13s | 0.483 GiB | 1 | 1000 | 437 |

One-worker wall time / eight-worker wall time: **1.053**. This is one
measurement per configuration. The eight-worker pool reached only two live
workers with the current batch plan; most execution was serial.

## Input and settings

The first 1,000 importer entries end at original Mathlib NDJSON line 66,309.
The prefix was copied verbatim, retaining complete declaration families.
SHA-256: `153e26a441664f09bb67f363f54c02c53a7f15d7920fff209846c6a3a5f7835f`.

Both runs used batch capacity 128, a shared 16 GiB memory budget, a 1.5 GiB
reservation per worker, a 1 GiB coordinator reservation, no workload swap,
a 600-second declaration timeout and a six-hour total deadline. The conversion
heuristic option was off in both. Foundation building, input indexing, checking,
discovery retries, artifact loading/saving and the final join are included.
The table uses the runner's measured wall times consistently for both runs;
outer guard startup/cleanup and shared input-prefix extraction are excluded.

The complete commands and toolchain fingerprints are in [commands.json](commands.json).
Raw results: [eight workers](workers-8/result.json), [one worker](workers-1/result.json).
Guard logs: [eight workers](workers-8.log), [one worker](workers-1.log).
Machine-readable comparison: [comparison.json](comparison.json).

## Fix and regression

Commit `98fcc0d` on `feature/distributed-import` restricts parent ownership to
actual inductive recursors. Ordinary definitions such as `Quot.rec` keep their
own source identity and specialization mask. Previously, `Quot.rec` was routed
to `Quot`, causing `Lean batch: missing instance owner entry` in the 500,000-line
experiment.

The new ordinary-definition regression failed with the old binary and passes
with the fix. All five real compiler integration cases and all 21 Python unit
tests pass. Evidence: [before log](regression-before/ordinary_rec_named_parallel.launcher.log)
and [after results](regression-after/integration-results.json).

The earlier 500,000-line eight-worker run failed after 533.53 seconds; its
one-worker comparison was cancelled when the user requested this smaller test.
Those incomplete runs are not used to calculate this comparison.
