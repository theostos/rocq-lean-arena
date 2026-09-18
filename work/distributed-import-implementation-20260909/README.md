# Distributed importer implementation and integration evidence

Implementation: `_worktrees/rocq-lean-import/distributed-import`, branch
`feature/distributed-import`, implementation commit `3b1b107`. Its baseline is
`6ca0051`, an isolated snapshot of
the current CSLib importer. The active original importer checkout was preserved.
See [the runner instructions](../../_worktrees/rocq-lean-import/distributed-import/tools/README.md).

The ContDiff run was stopped at the user's request on 2026-09-09. Its preserved
[result](../mathlib-contdiff-repro/faithful/20260909T125651261413Z/result.json)
records exit 143. It was not restarted.

## Evidence

* Plugin compilation succeeded against `compact-peano-view`; see
  [build log](plugin-build-v2.log).
* 21 Python unit tests pass, including malformed input, coverage, scheduling,
  failed/stale reports and process cancellation. Invalid guard worker limits
  0, 65, -1 and nonnumeric input are rejected. `bash -n` and `git diff --check`
  pass.
* [Compiler integration results](integration-v3/integration-results.json): serial
  and two-worker diamonds, one provider shared by two SProp consumers, and an
  invalid body returning kernel rejection/status 1. Two-worker fixtures recorded
  two live workers. The [final-source rerun](integration-final/integration-results.json)
  also passes all four cases.
* [Registry and regression results](registry-v2/results.json): reverse load order,
  duplicate entry ownership and batch identity rejection, incompatible universe
  contexts rejected on join, plus eight existing sequential importer regressions
  using the full foundation. The first registry harness run expected different
  wording for the universe error; the compiler correctly rejected it. Logs remain
  in `registry-v1/`.

## Real CSLib input

The unchanged full Arena certificate was indexed and planned:

| Property | Value |
|---|---:|
| Original certificate lines | 22,828,705 |
| Expression nodes | 21,039,124 |
| Importer entries | 253,649 |
| Named constants | 262,983 |
| Initial batches, capacity 128 | 2,071 |
| Indexing wall time | 1,098 seconds |
| Indexing plus planning wall time | 1,192 seconds |

Input SHA-256:
`cb677997476de3e79ce08b061757334d0777a8f1d8ec0d34da6a5f345a7f3483`.
See [full scan log](full-plan.log) and [plan](full-plan.json). This was a
structural scan, not a full proof check.

The first 100 declaration records were copied verbatim to
`cslib-first100.ndjson`. They contain 97 importer entries: four quotient records
form one entry. Both runs below built the full foundation and saved the final
aggregate, using batch capacity 8 and an 8 GiB aggregate memory budget.

| Check | One worker | Two workers |
|---|---:|---:|
| Accepted entries | 97 | 97 |
| Committed artifacts | 53 | 53 |
| Attempts, including discovery retries | 91 | 91 |
| Total wall seconds | 172.98 | 136.59 |
| Compiler CPU seconds | 168.35 | 159.36 |
| Peak cgroup memory, KiB | 410,004 | 726,612 |

Results: [serial](cslib-first100-serial/result.json),
[parallel](cslib-first100-parallel/result.json). These are single cold batch runs
on a small dependency-heavy prefix, not a full CSLib benchmark or a comparison
against the original monolithic importer. Indexing is included. The proof runs
precede the last input-validation tightening; the final stricter planner accepts
the same prefix in `strict-prefix-plan/`. Translation code is unchanged.

The first implementation fails closed on dynamically discovered dependency
cycles; automatic splitting, measured-cost scheduling, remote execution and
Arena container integration remain follow-up work. Full CSLib acceptance and
speedup have not been established.

## Continue the full experiment

From the main workspace, with no other guarded experiment running:

```sh
python3 _worktrees/rocq-lean-import/distributed-import/tools/parallel_import.py \
  _deps/lean-kernel-arena/_build/tests/cslib.ndjson \
  --output work/cslib-distributed-two-workers \
  --rocq _worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq \
  --stdlib _worktrees/rocq/stdlib-int32-repro/theories \
  --workers 2 --batch-entries 128 \
  --memory-mib 16384 --worker-memory-mib 4096 \
  --coordinator-memory-mib 2048 --timeout 21600 --line-timeout 600 \
  > work/cslib-distributed-two-workers.log 2>&1
```

The output directory must be new. Preserve `result.json`, the aggregate `.vo`,
all attempt logs and the guard log. Compare with a separate cold `--workers 1`
run using identical kernel options and certificate. No full run was launched
as part of these integration checks.
