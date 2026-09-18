# Mathlib 11M memory failure

## Observed failure

The latest canonical run exited with **125**, not a declaration timeout.
The memory supervisor stopped its worker at **15,732,964 KiB RSS**, above the
15 GiB soft threshold within the 16 GiB/no-swap guard. The last declaration
was `IsCyclotomicExtension.Rat.ncard_primesOver_of_prime_pow`, NDJSON line
11,289,804. Checkpoints through **11,000,000** are saved and reloaded.
Original logs: `../mathlib-ndjson/attempts/20260911T020943010532Z/`.

## Cause

The restored transitive-dependency cache represents each reachable constant
using tree-based name sets. Dense graphs duplicate these trees across cache
entries, retaining gigabytes and spending time repeatedly merging them.
This cache guides unfolding; it is not the importer's declaration registry.

The baseline allocation replay, `prefix-3c3uulub/`, measured
**310,205,999 reachable words (2.31 GiB)** for 31,505 cache entries at CPU
302.253 seconds. Sampled live allocations identify dependency-set/map nodes.
The replay was deliberately stopped after enough evidence was collected;
`diagnostic-cut.json` distinguishes that stop from a real timeout or guard failure.

An additional cold, dependency-only replay (`lazy-a79kn5vl/`) reached its
180-second diagnostic budget while building these sets. That replay skipped
unneeded declarations and is **not** the original eager-run failure.

## Repair

`kernel-fix.patch` changes only `kernel/environ.ml`, relative to the worker
that produced the failed run. Exact transitive sets are stored as immutable
bit strings, with an environment-local name-to-bit map. Direct references are
deduplicated before their transitive bitsets are merged.

- Warm queries still use cached transitive membership, not repeated graph search.
- Environment forks copy their cache state, including the bit numbering.
- Replacing a definition, or defining a previously missing referenced name,
  invalidates affected-generation caches without changing older environments.
- Unmarshalling rebuilds process-local cache data as needed.
- The existing shared-expression traversal safeguard is preserved.

Proof bodies, importer inputs, conversion rules, timeout/memory limits, and
checkpoint representation/seals are unchanged. Temporary allocation and memory
instrumentation is retained in separate diagnostic workers, not the final worker.

## Validation

The dependency tests cover positive/negative answers, canonical-name aliases,
shared expressions, forks, body replacement, missing-name definitions, and
unmarshalling. The existing 1,500-node chain retained **55,983 words**, versus
**12,384,750 words** with tree sets (about **221 times less**).

The final, uninstrumented worker passed:

- The expanded dependency suite, including a 160-node graph checked against
  an independent reachability matrix and a cache-memory regression bound.
- All **20 focused kernel regressions**.
- All **44 importer/CSLib regressions**, including the previously sensitive
  UTF-8 and bitvector-adder cases.
- The runner suite: **201 tests**, 2 skipped.

Records are under `validation-ok9bb35w/`. The first bitset candidate also
passed the 9M checkpoint reload in
`../mathlib-original-dependency-cache/checks-c78ihcu2/`.

The eager replay from 11M, `full-vojwyug0/`, preserves the original module name
and declaration order. The unchanged failing theorem now checks in **310.035
CPU seconds**, including its on-demand dependencies (CPU 657.766 to 967.801).
This is below the unchanged 1,800-second declaration limit. The scalar memory
probe was enabled for this measurement; allocation sampling was disabled.

Compilation and saving succeeded. The complete replay, including prefix
checking and saving, took **1,134.784 wall seconds**, with **4.57 GiB peak
cgroup memory**. See `full-vojwyug0/result.json` and `run.log`.
The fresh-process reload with the final worker also succeeded, including
unpacking and re-saving the importer state:
`full-vojwyug0/Reload.result.json` and `Reload.run.log`.

All **11 original checkpoint seals** verify unchanged:
`verified-checkpoints.json`. The canonical Mathlib run remains paused at 11M;
this isolated replay has not validated the remainder of Mathlib or a full CSLib
run.

The normal uninstrumented worker is SHA-256
`f8b61efc2d7c33f61f794be5f81d6a0d0f78c2f60ddcd64f43776f6f5212518a`.

## Reproduce and resume

From the repository root, replay every declaration from the 11M checkpoint
through the original failure, with the same timeout and memory limits:

```sh
python3 work/mathlib-11m-investigation/reproduce.py --mode full --line-timeout 1800
```

To resume the normal million-line checkpoint chain:

```sh
bash work/mathlib-11m-investigation/resume.sh
```

This helper requires matching regression and fresh-reload records, pins the
tested worker, and keeps the original checkpoint seals and all resource guards.
Use `--check` to check the repair handoff without launching a run.
