# Manual full cslib run

The previous complete-input attempt failed at line 11,005,951. The importer
fix passes the original dependency-only reproduction and selected regressions;
complete cslib compatibility is not yet established. The kernel remains the
modified experimental kernel. No full retry is running as part of this handoff.

From the repository root, start the independent service:

```sh
bash work/cslib-full-fresh/start-checkpointed-service.sh cslib-unit-fix
```

The command prints the service name and service log path. The service continues
without Codex monitoring; keep the Codex goal paused. Only one guarded Rocq
worker runs at a time. Stopping the service also stops its bound worker scope.

## What it runs

1. Fresh import up to, but excluding, line **11,005,951**; save `Prefix.vo`.
2. Load that prefix and import from **11,005,951** to EOF; save `Complete.vo`.
3. Load `Complete.vo` in another fresh Rocq process; save `Reload.vo`.

The split is immediately before the original failing declaration, not inside
a mutually declared inductive group. The full input is still checked, and the
original library proofs are unchanged. This keeps one prefix snapshot, not
the old chain of 27 accumulated snapshots. Saving the full-size prefix and
finishing under these limits remain untested until this run is executed.

Safety/performance settings:

- 16 GiB cgroup hard limit; preventive aggregate RSS stop at 15 GiB.
- Stop if system `MemAvailable` drops below **6 GiB**; no workload swap.
- Admission requires at least **22 GiB available** (16 GiB budget + 6 GiB reserve).
  If other applications need more memory, the guard refuses/stops this job.
  It never kills unrelated processes or relaxes limits automatically.
- `OCAMLRUNPARAM=s=4M,o=80,i=15,a=2,v=0`: less aggressive GC than the old `o=5`,
  without the repeated major-GC messages.
- 600-second per-declaration timeout; eight-hour deadline for each stage.

Watch logs manually (after `latest` has been created):

```sh
tail -n 5 -F work/cslib-full-fresh/runs/cslib-unit-fix/latest/*.log
```

`Ctrl+C` stops viewing logs, not the computation. To stop the actual job, use
`systemctl --user stop SERVICE_NAME` with the exact name printed at launch.

## Resume after a later failure

Once `Prefix.vo` and `prefix.sha256` have been saved successfully:

```sh
bash work/cslib-full-fresh/start-checkpointed-service.sh cslib-unit-fix --resume
```

This restarts at the saved split, **not** at the last printed declaration.
It checks the export, toolchain, driver and checkpoint hashes before resuming.
Changing the importer/kernel may invalidate this checkpoint or require rechecking
earlier translations; do not bypass these checks. If the prefix itself failed,
there is no new checkpoint: use a fresh tag for another full attempt.

Old artifacts and logs are preserved. Attempts get separate directories;
`latest` points at the newest attempt. A local launcher lock and the global
heavy-workload guard prevent concurrent checking jobs.

## Result to report

Send the service log and `runs/cslib-unit-fix/latest` when it finishes or fails.
Success requires all three stages to exit zero and atomically save their `.vo`
files. The final import must reach `List.pairwise_le_finRange`, line 22,828,731,
with **1,532,052 names** and **21,039,124 expression nodes**, no errors/skips,
and matching input/toolchain/artifact hashes. `Done!` alone is not enough.
The saved manifests and per-stage logs support that later audit; the launcher
is not an independent proof checker or a soundness certification.

## Launcher checks performed

The same three-stage launcher passes on the unchanged 10,248-line cslib
reproduction, split at its final declaration (`finloop_harness_smoke_v2`).
These functional tests use a 4 GiB diagnostic budget. A separate attempt with
the 16 GiB default correctly refused admission when available memory briefly
fell below 22 GiB (`finloop_harness_smoke`); it started no Rocq worker.
The shared memory guard's service-cancellation behavior was tested previously
and remains unchanged. Full-library completion is not claimed by these tests.
The explicit `--resume` path also passes on the same saved prefix without
repeating the prefix import. A mismatched resume split is rejected before any
Rocq worker starts.
