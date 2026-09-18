# Mathlib import: slow declarations

Read-only audit of 92 logs, including all 23 NDJSON checking/reload logs across
four attempts. Initial snapshot: 2026-09-10 07:12:54 UTC; completed-failure
follow-up below. The two fixed correctness
errors (`Std.ExtDTreeMap`, `StructuredArrow.homMk._proof_1`) are separate.

## What is expensive

### 1. One input declaration can trigger thousands of checks

`ContDiffAt.real_of_complex` takes **1,229.2 CPU seconds** with the 1,800-second
limit. Its own final Rocq declaration check takes **15.1 seconds**. The same
input also declares **3,860 dependency instances**. Across all 3,861 declarations,
`quickdef` accounts for **1,104.9 seconds (90%)**, and universe-context construction
for **84.1 seconds**. The slowest dependency check is
`iteratedFDerivWithin_eventually_congr_set'`, instance 7: **126.8 seconds**.

The timeout covers `add_entry`, including recursive `ensure_exists` calls.
It is not a fresh allowance for every demanded instance. The 600-second run
therefore expires before reaching the target's final check. Its alarm happens
in universe construction, but that does **not** make universes the main cost.

[Evidence: successful declaration-phase trace](snapshots/work/mathlib-ndjson/attempts/20260909T201749205324Z/MathlibTo5000000.run.log),
[timeout trace](snapshots/work/mathlib-ndjson/attempts/20260909T181350562244Z/MathlibTo5000000.run.log).

### 2. Dependency-guided unfolding is itself expensive

**41 of 63 pre-completion stack samples** are inside dependency reachability:
`Conversion.indirectly_depends_on → Environ.constant_depends_on → search`.
This appears in the calculus/analytic imports and again in measure theory.
These are biased, sparse samples, including repeated attempts—not a CPU percentage.

The code already caches direct edges and 16,384 reachability answers. However,
each cache miss can traverse the full reachable dependency graph: the outer
1,024-visit closure-inspection budget does **not** bound this inner search.
Answer tables are also reset when a constant is added. This identifies a concrete
optimization target; the logs do not yet quantify cache misses versus eviction.

| Input | Observed cost | Result |
|---|---:|---|
| `ContDiffAt.real_of_complex` | 20.5 min CPU, measured | Passes at 1,800 s |
| `Complex.contDiff_exp` | ≥10.5 min between samples | Passed |
| `ContDiffAt.exp` | ≥15.3 min between samples | Passed |
| `ContDiff.cexp` | ≥12.3 min between samples | Passed |

[Code: dependency cache and search](snapshots/_worktrees/rocq/compact-peano-view/kernel/environ.ml),
[all sampled slow inputs](slow-inputs.tsv).

### 3. Representation theory shows a different conversion bottleneck

`Representation.LinearizeMonoidal.μ_rightUnitor` has three samples spanning
four minutes, all inside recursive conversion; it eventually passes.
`Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq` has the same pattern and had
gone **28.3 minutes without a new declaration message** at capture time. It
subsequently **hit the 1,800-second timeout**. The alarm stack is still in
recursive conversion, unfolding a primitive projection.

Its samples repeatedly show `ccnv → eqwhnf → convert_stacks`, including
successful-conversion cache lookup and allocation/GC. They do not show dependency
graph search. The existing congruence budget limits **nesting depth to 256**,
not total work: the counter is restored on return. Broad/repeated argument
comparisons can therefore remain expensive.

That is a supported explanation to investigate, not yet proof of the exact
bad comparison. These logs lack the compared terms and target-specific phase
timings; a demanded dependency could still own the expensive check.

[Evidence: representation-theory stacks](snapshots/work/mathlib-ndjson/attempts/20260910T061532993791Z/MathlibTo10000000.run.log),
[completed timeout](follow-up/MathlibTo10000000.run.log),
[code: congruence budget and conversion](snapshots/_worktrees/rocq/compact-peano-view/kernel/conversion.ml).

The loop paused automatically; the validated **9M checkpoint remains**. No
process was stopped or restarted for this audit. A [31-minute laptop suspend](follow-up/suspend.log)
occurred before the alarm; that extra wall-clock gap is not checking time.

### 4. Checkpoint work is not theorem-checking time

Thirteen samples occur **after `Done!`**, in `pack_lean_state`, graph indexing,
hashing or GC. An empty reload import also repacks the whole prefix. The 9M
reload worker alone is observed for about 2.5 minutes. Seal verification
additionally rehashes the 5.6 GB export for each saved checkpoint.

These pauses must not be attributed to the last theorem printed. Increasing
the per-line timeout does not address them. RSS stays well below the 16 GiB
cap in this capture (maximum sampled RSS: 4.9 GiB); the logs do not indicate
memory-limit throttling as the explanation.

## Reproduce, without changing the running experiment

[Reproduction instructions](REPRODUCE.md) preserve the original export, parent
checkpoints, chunk module names and recorded worker hashes. The runner defaults
to a dry run and refuses concurrent compilation. No proof bodies are replaced.

First measure dependency-query CPU/misses on `contdiff`; then isolate the
conversion/declaration phase on `rep-resolution`. Treat checkpoint packing as a
third, independent benchmark. No optimization or new compiler run was performed
for this audit; the replay harness has only been dry-run validated.
