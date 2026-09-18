# Restore the original dependency cache

`kernel/environ.ml` again stores transitive dependency sets, as in the Rocq
baseline `f756383de2`. Queries use set membership; cached sets survive additions
to the environment. The bounded source/target answer table and repeated graph
search are removed. The separate shared-term traversal safeguard is retained.
Other kernel patches and the importer are unchanged.

This changes heuristic caching, not conversion rules or saved declaration
layouts. The cache is process-local. Existing checkpoint seals are not rewritten.
Memory consumption can increase; the 16 GiB/no-swap guard remains enforced.

## Validation

- Kernel rebuild passed under a 4 GiB guard.
- Dependency semantics, environment isolation, shared terms and chain tests
  passed: `checks-f6sfhytz/dependencies.log`.
- All 20 existing regression checks passed:
  `../structured-arrow-repro/patched-checks-3zdevl0h/results.json`.
- The existing 9M checkpoint loaded successfully and a new definition compiled
  with the rebuilt worker: `checks-vdludtxh/`.
  The first reload fixture used an unqualified `I`, shadowed by an imported
  declaration; the corrected fixture uses a local identity proof.
- All nine original seals verified without changes: `verified-seals.json`.

No full import or performance replay was launched. In particular, this has not
yet been shown to fix the timeout on
`Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq`.

## Resume

From the repository root:

```sh
bash work/mathlib-original-dependency-cache/resume.sh
```

This reuses the 9M checkpoint and retries the 9M–10M interval with the existing
1,800-second timeout and million-line checkpointing. It pins the tested worker
through the existing kernel-migration mechanism; all other input checks remain.

Progress and logs remain under `work/mathlib-ndjson/latest/`.

New worker SHA256:
`ae3b7e159bd7eb582971ab86cf13abaf71dc435f2d5cc0cd3d8e184b0df44df5`.
The previous worker and source are retained as `rocqworker.before.exe` and
`environ.before.ml`. No commit or push was made.
