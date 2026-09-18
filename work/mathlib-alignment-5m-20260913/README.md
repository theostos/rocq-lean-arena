# Fresh Mathlib verification — 13 September 2026

Outcome: failed at line 11,422,301, `CategoryTheory.WithTerminal.instCategory._proof_2`,
after passing 5M and 10M save/reloads. Superseded by the repaired, fresh line-1
generation in `../mathlib-alignment-5m-20260913-with-terminal`. This generation's
artifacts remain historical evidence; they are not seeds for the new full run.

Started at 10:51 Paris time, from line 1 through the 100,001,405-line export.
No historical seed. Checkpoints every 5,000,000 lines, each sealed and reloaded
in a fresh worker before continuing. No proofs are skipped.

- User service: `rocq-mathlib-alignment-5m-20260913.service`, `Restart=no`.
- Worker: `b02396916069318a4fddd34514ecd937a5294a504384fee31caecfdb62888cb5`.
- Importer: `../kernel-alignment-pass/importer.42J4K0w1`; plugin SHA256
  `b17738e6278ee0df0984fbdac06653001f1a1d29eb046bb2f241d86f1d5d4cde`.
- Limits: 1,800 seconds/declaration, eight hours/chunk, 15 GiB aggregate RSS,
  16 GiB memory cgroup, zero swap.
- Validation: `../kernel-alignment-pass/final-gates-19/passed.json`, independent
  native checks in compatibility and strict-with-explicit-UIP modes, strict CLI
  controls, and the original-order target-to-6M replay plus fresh reload in
  `../mathlib-lift-to-discrete-repro/`.

This replaces the September 12 generation, which failed at line 5,816,190.
Its checkpoints and diagnostics are retained as evidence, not used as seeds.
Full Mathlib acceptance and exact kernel equivalence are not yet established.
About 9 GiB remained free at launch; the disk safety guard may stop the run
before EOF unless more space becomes available. The runner does not delete
checkpoints automatically.

## Progress

Read `progress.json` for the current declaration and checkpoint position,
`latest/` for current-attempt logs, `checkpoints/` for the saved chain, and
`result.json` for the eventual result. No ongoing assistant monitoring or repair
is scheduled; model-free progress and diagnostic logging remain enabled.

```sh
python3 scripts/mathlib_ndjson_loop.py status --directory work/mathlib-alignment-5m-20260913
journalctl --user -u rocq-mathlib-alignment-5m-20260913.service --no-pager
```

To stop both the supervisor and guarded worker:

```sh
systemctl --user stop rocq-mathlib-alignment-5m-20260913.service
```
