# Reproduction

Run from the repository root. Log analysis is safe during compilation:

```sh
python3 work/mathlib-log-audit-20260910/analyze.py
```

This reanalyzes the frozen snapshots listed in `manifest.json`, not changing
live logs. `analysis.json` includes declaration CPU stages and every captured
stack; `slow-inputs.tsv` and `worker-times.tsv` summarize them. Sample spans are
lower bounds, not full declaration durations. Worker spans exclude some startup,
shutdown and supervisor hashing time; the last chunk was still running at the
initial snapshot. `follow-up/` preserves its subsequent timeout separately,
including the system-suspend interval; do not treat that interval as CPU time.

## Replay a checking interval later

```sh
python3 work/mathlib-log-audit-20260910/reproduce.py contdiff
```

Without `--run`, this only prints the source and worker identity. After the
full import stops, append `--run`:

```sh
python3 work/mathlib-log-audit-20260910/reproduce.py contdiff --line-timeout 600 --run
python3 work/mathlib-log-audit-20260910/reproduce.py contdiff --line-timeout 1800 --diagnostics --run
python3 work/mathlib-log-audit-20260910/reproduce.py rep-resolution --diagnostics --run
```

| Case | Parent checkpoint | Last NDJSON line checked |
|---|---:|---:|
| `contdiff` | 4,000,000 | 4,855,906 |
| `analytic` | 4,000,000 | 4,886,805 |
| `cexp` | 5,000,000 | 5,128,889 |
| `rep-unitor` | 9,000,000 | 9,187,892 |
| `rep-resolution` | 9,000,000 | 9,239,031 |
| `reload9m` | 9,000,000 | Empty import; measures unpacking/repacking |

Every replay checks the **entire interval** after its parent, preserving the
original chunk's module name. It is not a dependency slice or a minimal example.
Earlier dependency-only/axiomatized ContDiff controls passed quickly and did
not reproduce the full-run timeout.

The runner checks the export, toolchain inputs and parent seals, takes the same
exclusive launcher lock, and uses one memory-guarded worker: 16 GiB, no swap,
3 GiB system reserve, two-hour outer timeout. It never overwrites checkpoints
or restarts the full loop. Sources, logs, invocation hashes and any resulting
`.vo` go into a new audit subdirectory. No extra monitoring or model is started.

`--diagnostics` enables existing declaration CPU stages, scalar dependency
counters and checkpoint-stage timings. It does not enable the memory-heavy
conversion-pair trace. Compare an uninstrumented replay if measuring overhead.
The harness was inspected and dry-run tested; no new checking replay was run.

## Recorded inputs

- Mathlib: `8a178386ffc0f5fef0b77738bb5449d50efeea95`, Lean 4.29.0.
- NDJSON: `100001405` lines; SHA256
  `a466d22a521f0fc0406b6d0ece2173f2b2e3d9eb4d8bc26a5e14316d39944d27`.
- Importer plugin: SHA256
  `568bd9c9e537aa54f304a8488e56d9251341400bf3032b1fe939228bcc83d5a2`.
- Analytic cases use the retained pre-alias-fix worker, SHA256
  `78cfbfb0660e84e0c62e110fd1e60b3262057b815f5f3deda10edf48fccb8ad7`.
- Representation/reload cases use the patched worker, SHA256
  `2d631c655cb65e6b1998886414c36ef10e5a322826b613e338a15009cc090c9f`.

The exact local paths are in `reproduce.py`; frozen source excerpts and their
hashes are listed in `source-manifest.json`. Kernel source snapshots match
their built-source copies. The earlier worker differs by the unit-alias fix;
the analytic slowdown was already present before that change.
