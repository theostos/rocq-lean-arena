# Fresh Mathlib run after the WithTerminal repair

Started September 13, 2026 at 15:05:19 Paris time. The service is active and
the first 5M chunk has started. Full Mathlib acceptance remains pending.
Startup was verified through declaration line 85,111, with plan start=1,
interval=5,000,000 and seed=null. No further assistant monitoring was performed.

This generation starts at line 1 of the pinned 100,001,405-line export, with
no historical checkpoint seed. Checkpoints every 5,000,000 lines are sealed
and reloaded in a fresh worker before continuing. No proof-skipping option is
enabled. The existing importer's theory/translation settings are retained.

- Service: `rocq-mathlib-alignment-5m-20260913-with-terminal.service`, `Restart=no`.
- Worker SHA256: `938cf20b10fc8ebcde26d325e797057e79d59e42b1a2078613ff7f53222fe5ac`.
- Importer: `../kernel-alignment-pass/importer.lFy9zJVL`, rebuilt from unchanged
  sources for the current kernel interface. Plugin SHA256:
  `eb1304b3d18802a18b67bde55e5d4c2e630122e298cd199d0a1d03d90fa8dd9f`.
- Limits: 1,800 seconds/declaration, eight hours/chunk, 15 GiB aggregate RSS,
  16 GiB memory cgroup, zero swap; existing disk-admission guard retained.
- Validation: `../kernel-alignment-pass/final-gates-20/passed.json` and
  `../mathlib-with-terminal-repro/README.md`.

Important: strict independent checking rejects imported declarations carrying
the pre-existing disabled-elimination-check flag. The theorem slice independently
passes in the existing compatibility profile; the native fixtures pass strict
checking with explicit UIP. This run is not a claim of strict-theory certification,
exact kernel equivalence, or completed Mathlib acceptance.

Only startup will be verified by the assistant. Model-free progress/resource
logging continues; no ongoing assistant monitoring or repair loop is scheduled.
Around 7 GiB was free during preparation. The disk guard can stop the run before
EOF if checkpoint storage exhausts the available headroom; it deletes nothing.

## Progress

Read `progress.json` for the current declaration/checkpoint, `latest/` for the
current attempt's logs, `checkpoints/` for the saved chain, and `result.json`
for the eventual outcome.

```sh
python3 scripts/mathlib_ndjson_loop.py status --directory work/mathlib-alignment-5m-20260913-with-terminal
journalctl --user -u rocq-mathlib-alignment-5m-20260913-with-terminal.service --no-pager
```

To stop the supervisor and its guarded worker:

```sh
systemctl --user stop rocq-mathlib-alignment-5m-20260913-with-terminal.service
```
