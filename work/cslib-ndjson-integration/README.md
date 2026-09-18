# Direct NDJSON cslib integration

Goal: reproduce the successful converter-based cslib check using direct NDJSON input.
The full direct-NDJSON pass is not yet validated.

Local importer branch: `integration/cslib-ndjson`, based on `submit/ndjson`.
The existing runtime importer and custom kernel worktrees were not changed.
The published submission branches were not changed or pushed.

The integration uses the current runtime translation code, shared chunked parser
indices, and explicit NDJSON mutual blocks. Theorems retain the converter's
`OpaqueHint` with `kernel_opaque=false`; genuine opaque declarations remain opaque.
No proof is replaced or skipped.

## Checks

`checks-nfv8_ggd/guard.log`: eight fixtures, 619 matching declarations and 19,898
matching expression pairs. Both routes compiled; direct outputs reloaded in a
fresh process. The Unit fixture includes two rejected invalid equalities per route.
One worker at a time; 4 GiB guard, measured cgroup peak 213,500 KiB.
`manual-smoke/result.json`: the public runner also completed the `Nat.beq`
reproduction successfully (fresh foundation and `Full.vo`, 1 GiB guard).

Fixtures cover binary trees, mutual inductives, nested records, mixed nested
fields, `DiscrTree.casesOn`, `Nat.beq.eq_def`, nullary unit elimination and
quotient-valued records. These are focused regressions, not a full-library proof.

## Commands

From the workspace root:

```sh
bash work/cslib-ndjson-integration/build.sh
python3 scripts/run_cslib_ndjson.py
```

The runner reuses the existing cslib NDJSON, starts at line 1, fails on errors,
uses no input checkpoints, and keeps the existing 16 GiB/single-worker guard.
It saves fresh `Full.vo` output only after compilation succeeds.

```sh
tail -n 5 -F work/cslib-ndjson/latest/{Full.run,guard}.log
```

To rerun the focused checks:

```sh
bash work/cslib-ndjson-integration/build-compare.sh
python3 work/cslib-ndjson-integration/regressions.py
```

The build uses the existing compatible Yojson installation; override
`NDJSON_YOJSON_DIR` when setting it up on another machine.
