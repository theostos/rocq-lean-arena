# Fresh Mathlib run — 12 September 2026

**Stopped on a checking error at line 5,816,190**, after a successful 5M save
and fresh reload. This is historical failure evidence, not the current run.
The regression and repaired-worker validation are recorded in
`../mathlib-lift-to-discrete-repro/README.md`.
The replacement run is `../mathlib-alignment-5m-20260913`, with its own
`progress.json`; this directory's status will not track the replacement.

User-requested run from line 1 to EOF (100,001,405 lines), without a historical
checkpoint. Checkpoint interval: 5,000,000 lines. Every completed checkpoint is
sealed and reloaded in a fresh worker before continuing. No proofs are skipped.

- User service: `rocq-mathlib-alignment-5m.service`, `Restart=no`.
- Declaration timeout: 1,800 seconds; process timeout: eight hours per chunk.
- Limits: 15 GiB aggregate RSS, 16 GiB memory cgroup, zero swap.
- Worker: `3a9480ea6f86050019bf78e3be3c0dc254ccb96b4cad361e99af1e862dc637dd`.
- Importer: `../kernel-alignment-pass/importer.42J4K0w1`;
  plugin SHA256 `b17738e6278ee0df0984fbdac06653001f1a1d29eb046bb2f241d86f1d5d4cde`.
- Evidence: `../kernel-alignment-pass/final-gates-16/passed.json`;
  updated runner suite: 204 passed, two skipped.

This is an experiment, not a claim of full Mathlib acceptance or exact kernel
equivalence. It stops on a checking error, resource limit, input change or
insufficient disk space. No assistant monitoring or automatic agent repair is
scheduled. The runner's model-free progress and diagnostic logging stays active.

Read `progress.json` for progress, `latest/` for the current attempt's logs,
`checkpoints/` for the new chain, and `result.json` for the eventual result.
Supervisor output is available with:

```sh
journalctl --user -u rocq-mathlib-alignment-5m.service --no-pager
```

To stop the run and its guarded worker:

```sh
systemctl --user stop rocq-mathlib-alignment-5m.service
```

All 37 old Mathlib compiled checkpoint artifacts were deleted before launch at
the user's request (6,710,183,007 bytes). Sources, exports and logs are retained;
recovery requires rebuilding. The exact deletion audit is
`../kernel-alignment-pass/mathlib-checkpoint-cleanup-20260912.json`.

The preceding `full-eta-substitution` replay was intentionally stopped by the
user at line 21,116,444. Its termination was not a kernel failure.
