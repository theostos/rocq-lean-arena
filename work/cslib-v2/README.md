# cslib V2 import checkpoint

This directory contains the fresh, process-independent checkpoint chain for
the cslib import.  Heavy commands must go through `../run-memory-guarded.sh`
or `../run-checkpoint-atomic.sh`; do not invoke Rocq directly.
These checkpoints use the experimental kernel/importer worktrees. They do not
establish a complete cslib check with upstream Rocq.

## Fixed input

- Export: `_deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export`
- SHA-256: `ce6fb77ab3905e0dbbc9668dad42f3cbfee474c131b472140cc4da94f8b323ae`
- Physical lines: `22828731`
- Lean: `4.27.0-rc1` (`2fcce7258eeb6e324366bc25f9058293b04b7547`)

Before resuming, verify the input with:

```sh
sha256sum _deps/lean-kernel-arena/_build/tests/cslib-hints.lean-export
```

## Verified frontier

**Current runtime qualification:** the later Int32 division experiment changed
the runtime and regenerated Corelib. The preserved artifacts below require
the earlier foundation digests and are not currently reloadable against that
new Corelib. A separate coherent foundation and Int32 reproduction now pass; see the
[Int32 reproduction journal](../int32-tdiv-repro/README.md). Do not rerun the
historical full-pass command with this mixture of artifacts. This does not
change the saved frontier's file or establish a new checking frontier.

**Current canonical frontier: `CslibV2To9500000.vo`**, saved successfully on
September 6 with strict failure mode and missing-quotient skipping disabled.
SHA-256: `30c1394fbe2d6eda64912244bf6a522ac1c14fb0add6dca8a59ec50973a542be`.
It contains 94,241 entries (246,064 possible instances), 1,722 universe
expressions, 609,643 names, and 8,794,395 expression nodes. Checking and saving
completed at CPU 1,184.987, followed by successful atomic promotion. Peak
cgroup usage was 3,894,788 KiB (3.71 GiB), under the unchanged 4 GiB cap.
The 3.75 GiB preventive RSS limit, 13.5 GiB system reserve and swap prohibition
also remained active. Indexed checkpoints with exact-capacity reverse indices
and 5% major-heap growth (`i=5`) now pass this frontier's saving step. This does
not establish that the whole export will fit, or that upstream Rocq suffices.

The `9500000 10000000` continuation checked all 100,822 entries but its save
hit the preventive RSS limit during indexed encoding (exit 125); no 10M `.vo`
was promoted. A [fresh complete import](../cslib-full-fresh/README.md), without
loading the accumulated checkpoint chain, then stopped at `Int32.ofInt_tdiv`
(7,895,801) at the preventive RSS limit (exit 125). No full `.vo` was produced.
That original Lean declaration now passes in a controlled small reproduction;
the corrected fresh full replay is documented in the linked journal. The canonical
9.5M file is preserved; the fresh run is not a full-library result.
9.5M producer importer (constructor-owner fix and exact-capacity
checkpoint index):
`c50b61ef63d06f102ad33b7a4601e11d1550667fe93e14ff229c21ae3daad175`.
Experimental worker used for that checkpoint and the failed fresh pass:
`239ec13ec07713f0b8781711fb72ac615607140d725eb38a6d09cca6a84ab5d6`.
The historical `V2` filename prefix is retained; new saves use packed format 3.

### Earlier frontier history

`CslibV2To8500000.vo` was the preceding regular checkpoint in the canonical chain.
Its SHA-256 is:

```text
414df2d6005ba57c8d9843e07ab1070433fd873cad41684d30fc5a6e91f76bff
```

It contains 86,266 entries (225,986 possible instances), 1,599 universe
expressions, 561,937 names, and 7,850,199 expression nodes. The strict 8M-to-8.5M
continuation passed including atomic saving in about 706 CPU seconds, peaking
at 4,116,124 KiB (about 3.93 GiB), below the unchanged 4 GiB cap.

The newer pre-blocker checkpoint `CslibV2To8680510.vo` also passed and saved
(86,780 entries). The formerly failing bitvector-adder proof at 8,680,510 now
passes with two bounded heuristic probes, including the final refined worker:
`CslibV2AdderLambdaEligibility.vo` (86,781 entries, 202.331 CPU seconds through
saving). All four older targeted regressions and both small positive/negative
controls passed with that same worker. The hard cap remains 4 GiB, with a
3.75 GiB preventive RSS threshold and 13.5 GiB system reserve.
The regular 9M continuation has not passed: it progressed to 8,940,683, then
hit the 600-second declaration timeout on
`Std.Tactic.BVDecide.BVExpr.bitblast.goCache_Inv_of_Inv._mutual`.
It did not run out of memory: peak sampled RSS was 3,452,848 KiB (about
3.29 GiB); the scope remained capped at 4 GiB and exited with status 1.
No 9M checkpoint was promoted. `CslibV2To8940683.v` isolates the successful
prefix from 8,680,510, but its first save hit the cgroup limit while packing.
A GC-only checkpoint change reduced the heap but still hit the preventive
RSS limit during packing. The file-backed packing variant also exceeded that
threshold before finishing its write. The chunked parser index with explicit
old-checkpoint migration then passed the entire prefix and atomic saving under
the unchanged cap (765.309 CPU seconds). Its SHA-256 is
`3eeb3b9002d6debd5df0cbf42aab29ebc6ee2f2131d6cffb5c59c554c2b9b2a1`.
It contains 87,362 entries (227,736 possible instances). The one-entry
diagnostic at 8,940,683 now **passes translation and Rocq declaration checking
within the normal 600-second limit**, but saving its `.vo` exceeds the 4 GiB
cgroup cap. No new checkpoint was promoted. The numeric 8,940,683 checkpoint
remains intact (SHA-256 reverified after this failure); regression files remain
siblings, not additional ancestors. This is not a 9M or full-library pass.

The diagnostic sibling `CslibV2To7216963.vo` also saved successfully: 72,440
entries, ending immediately before the slow declaration at 7,216,963. SHA-256:
`4f3faa3dcbc812b594f6c482e491491771e97722b5d4ec74a6fca70eb64a7ead`.
Its peak was 3,554,300 KiB (about 3.39 GiB), below the same 4 GiB cap.

The attempted `3000000 4000000` continuation reached `Int16.toInt_lt` at
import position `3847801`, then raised `Stack overflow`.  That run inherited
an 8 MiB system stack.  Historical successful continuations used a larger
stack.  `CslibV2To3847801.v` stops immediately before the declaration, and
`CslibV2Blocker3847801.v` isolates it. That isolated test now passes with the
256 MiB stack; no change to the imported proof was needed. A control run
(`CslibV2Blocker3847801Stack8.v`) using the same current kernel and importer
reproduced the `Stack overflow` with an 8 MiB stack. This isolates the runtime
stack limit as the cause of this particular failure.

## Resume status

- The kernel rebuild after removing the remaining argument-overflow tracing
  completed with `-j1` on 2026-09-05.
- `CslibV2Load3000000.v` successfully reloads the checkpoint in a fresh Rocq
  process.
- `CslibV2To3000001.v` successfully forced the packed importer state in a fresh
  process with a 2 GiB cgroup limit (about 1.2 GiB observed RSS).
- `CslibV2To3500000.v` successfully continued from 3,000,000 with a 2.75 GiB
  cgroup limit, no swap, a 256 MiB stack, and a 13.5 GiB system reserve.
  The last observed cgroup usage was about 2.32 GiB.
- The first subsequent pre-blocker attempt was killed near position 3,628,266
  during a session interruption. No checkpoint was promoted; the exact kill
  cause was not retained. The retry saves both compiler and guard logs.
- The retry successfully produced `CslibV2To3847801.vo` (SHA-256
  `25f291d317442b16a5d1c29ffa8bb4602c9e882fd690e6244a5bcf26e95c8eec`).
  It imported 37,090 entries and used about 1.9 GiB of cgroup memory at the
  last sample. Compiler log: `CslibV2To3847801.retry.run.log`; supervisor log:
  `CslibV2To3847801.retry.guard.log`.
- `CslibV2Blocker3847801.v` then passed in a separate process, adding exactly
  `Int16.toInt_lt` (37,091 entries total). The continuation to 4,000,000 now
  starts at 3,847,802 and depends on this successful checkpoint.
- `CslibV2To4000000.v` then succeeded (38,851 entries total). The last observed
  cgroup usage was about 1.4 GiB.
- `CslibV2To4500000.v` succeeded (44,024 entries total), with about 2.1 GiB
  observed cgroup usage. The next continuation is `CslibV2To5000000.v`.
- The first 5,000,000 run reached `Done!` (49,563 entries) but exceeded the
  2.75 GiB cgroup cap while saving. The kernel journal confirms a cgroup-local
  OOM kill, and no `.vo` was promoted. This is not a usable checkpoint.
  Its retry uses `OCAMLRUNPARAM=s=8M,o=50,a=2`: a 64 MiB minor heap and more
  frequent collection than Rocq's default 256 MiB / `o=200` policy. The same
  hard cap remains in force. Retry logs are `CslibV2To5000000.gc50.*.log`.
- That retry succeeded and atomically saved the 5,000,000 checkpoint. The
  cgroup's recorded peak was 2,620,948 KiB (about 2.50 GiB), below the unchanged
  2.75 GiB cap. Use the GC setting above for subsequent continuations.
- No successful V2 log reports skipped declarations. Subsequent checkpoint
  sources also explicitly disable `Lean Skip Missing Quotient`, the exception
  to the importer's `Fail` mode, so missing quotient support cannot be skipped.

These results use the local experimental kernel in `compact-peano-view`;
they do not establish compatibility with an unmodified upstream Rocq kernel.

## Declaration timeout regression

`Lean Line Timeout` formerly wrapped only parsing, leaving declaration checking
unbounded after the pending-inductives refactor. `with_line_timeout` now also
wraps the declaration action inside `process_effect`; timeout errors use the
existing rollback/error-mode path and have an explicit diagnostic.

`CslibV2EntryTimeout.v` resumes from 4,000,000 with a one-second line timeout.
With the old plugin it was still checking after 30 seconds and was stopped by
the external timeout (exit 124). With the patched plugin it exited 1 at
position 4,000,622 with `Lean import line timed out.` The before/after compiler
and supervisor logs are retained next to the source. Neither run produced a
checkpoint. Both used the same input, GC settings, stack limit, and hard cap.

The rebuilt plugin SHA-256 is
`5c1494e673ea81c81c05a9ec12a36d57143b00b84a2215b92cac7e34c9972b70`.
Its build used one job and peaked at 149,368 KiB of cgroup memory.

## Closed arithmetic through projections

The continuation to 5,500,000 initially failed at position 5,402,976,
`Int32.toInt_lt`, with a stack overflow even at a 256 MiB stack limit.
`CslibV2To5402976.vo` now provides a fresh pre-blocker checkpoint (SHA-256
`f8e0f43a17efbcd2b5127a0f680d1eebcb94355902078d2dd52845f08c8ea31c`).

The isolated failure compared integer computations `2 * 2^31` and `2^32`
through primitive typeclass projections. The guarded weak-head reduction in
`kernel/conversion.ml` rejected projection stacks, so conversion compared
recursor branches instead of evaluating these closed computations. Allowing
`Zproj` alongside application/shift/update frames lets the existing closedness,
result-type, and registered-arithmetic checks handle them. No reduction rule
or proof was replaced.

`CslibV2Blocker5402976.v` fails with the old filter and passes with this change
(53,500 entries total, peak 2,444,416 KiB). Logs:
`CslibV2Blocker5402976.entries.run.log` and `.projection.run.log`.
`CslibV2To5500000.v` now resumes at 5,402,977 from that successful checkpoint.

The continuation to 5,500,000 passed checking but exceeded the 2.75 GiB cap
while saving with `s=8M,o=50,a=2`. It then successfully saved with the more
conservative `OCAMLRUNPARAM=s=4M,o=20,a=2` (32 MiB minor heap, `o=20`), peaking
at 2,747,436 KiB. This verified checkpoint contains 54,509 entries. Logs are
`CslibV2To5500000.gc20.run.log` and `.gc20.guard.log`.

The projection-only kernel worker SHA-256 was
`0388e25b207a4fd8167eabab91a52df8ca518da65d0b6362d5cf8bc1e77d578f`.

`CompactProjectedArithmetic.v` is only a smoke test: it passes both with and
without the change and must not be presented as the failing regression.
A smaller discriminating test and broader kernel regression testing remain
to be done. The `Stdlib.NArith.NArith.vo` aggregate in the local stdlib worktree
has an inconsistent `Corelib.Init.Prelude` dependency; avoid claiming a clean
full stdlib/test-suite rebuild from the current partial build artifacts.

## Dependency ordering before expensive conversion

The next continuation exceeded the cgroup cap while checking
`Int32.toBitVec_not`, position 5,534,591 (before checkpoint saving).
`CslibV2To5534591.vo` successfully isolates its prerequisites (SHA-256
`426064b5785d0c4cd4f4c7b835be5804c60caa444a77ef29b9524dddc0fbd7d0`).

The existing dependency-aware ordering had only been a late fallback. With
`Kernel Conversion Dep Heuristic` enabled, typed conversion now tries that
ordering first, retaining all the previous attempts if it reports failure.
This changes reduction order, not which equalities the kernel accepts.
The isolated `CslibV2Blocker5534591.v` passed and saved its checkpoint
(54,930 entries; peak 2,667,244 KiB); logs: `.depfirst.run.log` and
`.depfirst.guard.log`. `CslibV2To6000000.v` now resumes at 5,534,592.

The dependency-first worker used for these tests had SHA-256
`9e301c89c02e4db587bfb750c31f118002e8b74bb0e2fd8417dc89f363d15311`.
The earlier arithmetic case is rechecked in a separate module,
`CslibV2RecheckInt32Projection.v`, to avoid overwriting an ancestor checkpoint
that existing descendants depend on. It passed with the current worker
(peak 2,407,576 KiB). The small `CompactProjectedArithmetic.v` smoke test
also passed, including rejection of an unequal power equation; its logs are
`.negative.run.log` and `.negative.guard.log`. It is still not the
discriminating regression for the projection change.

The continuation to 6,000,000 with both fixes uses
`CslibV2To6000000.depfirst.run.log` and `.depfirst.guard.log`.
It was stopped by the RSS guard near position 5,885,362: aggregate RSS reached
2,886,544 KiB, exceeding the unchanged 2,883,584 KiB cap. This was during
checking, not saving, and no checkpoint was promoted. The last successful
checkpoint therefore remains `CslibV2Blocker5534591.vo`.

A retry (`CslibV2To6000000.gc5.*.log`) used
`OCAMLRUNPARAM=s=2M,o=5,i=5,a=2`, with the same cap, reserve, and single-worker
guard. This trades collection time for a smaller heap; it is not an increase
in the memory allowance. It was deliberately terminated after about five
minutes while still at `ENNReal.one_lt_two` (5,536,463), using about 1.9 GiB.
This is an interrupted experiment, not a completed check or an OOM failure.

## Direct dependency cache

The dependency heuristic used to cache the full transitive dependency set of
every visited constant. Even a chain can therefore retain quadratically many
set nodes. `kernel/environ.ml` now caches direct body dependencies and answers
reachability queries with a short-circuit, tail-recursive worklist. Existing
environment snapshot isolation and replacement invalidation are unchanged.
This affects the reduction-order heuristic, not the conversion rules.

`test-suite/unit-tests/kernel/constant_deps.ml` tests dependency semantics,
references to opaque constants, dependencies in binder types, cache invalidation,
old environments, and all pairs in a small DAG against an independent oracle.
Those tests passed before and after the change. A 1,500-definition chain
retained 12,384,750 OCaml words with the old cache and 34,489 with the new cache
(about 94.5 MiB versus 0.26 MiB on this 64-bit runtime). Logs:
`constant_deps.before.log` and `constant_deps.direct.log`. This is a measured
microbenchmark, not a claim that the full cslib import will save that ratio.
Repeated negative queries may become more expensive. A separate warm-query
measurement takes 1.428 CPU seconds for 1,000 negative queries on the same
1,500-node chain (`constant_deps.direct-warm.log`); this is an absolute cost,
not a before/after timing comparison. Integration timings still need checking.

The direct-dependency worker SHA-256 is
`4ff745ebd82dfd6ce6fd71bd18c50f90404f97d05182aea3d4f1ba1974ae62ce`.
`CslibV2RecheckInt32Complement.v` passed with that worker (peak 2,667,280 KiB).
`CslibV2RecheckInt32Projection.v` also passed (peak 2,409,448 KiB).
The 6,000,000 continuation now uses `CslibV2To6000000.direct.*.log`, with
`s=4M,o=20,a=2` and the same 2.75 GiB cap.
That direct-edge-only experiment was deliberately terminated after about
nine minutes at `EReal.add_lt_of_lt_sub` (5,618,537), using about 2.1 GiB.
It had not produced a checkpoint and was significantly slower than the
full-closure-cache attempt on this prefix.

To amortize repeated searches, `DepCache` now also keeps at most 1,024 completed
source/target answers per environment, clearing them when full. Both endpoints
use `Constant.UserOrd`, matching the existing environment maps and sets. Every
new environment gets an empty answer table, while direct-edge map snapshots
remain shared persistently. The answer bound is per live environment, not a
global bound across all retained snapshots.

The expanded unit test covers aliases with a shared canonical name, eviction,
and a cached negative query before appending a declaration. It passes. The
chain retains 34,502 words (about 0.26 MiB); 1,000 warm negative queries take
less than 0.001 CPU seconds at the printed precision, versus 1.428 seconds
without the bounded answer cache. Log: `constant_deps.bounded.log`.
The worker SHA-256 for this bounded-cache variant is
`731d1a72d822f873c1914207baed9b8ad8a3f5072a2da726ba4ff5efaa804a7f`.
The two isolated Int32 regressions also pass with this variant, including
checkpoint saving: complement peak 2,752,856 KiB; projection peak 2,429,900 KiB.
The continuation uses `CslibV2To6000000.bounded.*.log` with unchanged limits.
It completed checking 60,324 entries through position 6,000,000, but exceeded
the cgroup cap during saving (exit 137; cgroup-local OOM confirmed in the kernel
journal at 12:10:15 on 2026-09-05). No `.vo` was promoted. Near 5,880,000,
aggregate RSS was about 2.1 GiB, versus about 2.7 GiB with full closure caching.
This is progress in memory usage, not a successful 6,000,000 checkpoint.

## Checkpoint serialization headroom

The local OCaml 4.14.2 `runtime/extern.c` confirms that marshalling allocates
its sharing table with native allocations, outside OCaml GC heap accounting;
resizing temporarily keeps both the old and new tables. An experiment called
`Gc.compact ()` before `Marshal.to_string` to release unused heap space before
this allocation. The checkpoint schema and digest were unchanged.
The experimental importer SHA-256 was
`5ec6393063adf9ad0e98be3fdf633eee616e7f427d96eb76c87c8c671f00fac7`.
The isolated measurement uses `CslibV2RecheckInt32Complement.compact.*.log`.
It passed but reached a cgroup peak of 2,883,584 KiB, compared with 2,752,856 KiB
without the call. Since this did not demonstrate a saving, the compaction call
was removed; it is not part of the current importer.
The importer was rebuilt and its original SHA-256 restored:
`5c1494e673ea81c81c05a9ec12a36d57143b00b84a2215b92cac7e34c9972b70`.
The next retry, `CslibV2To6000000.bounded-gc10.*.log`, uses
`OCAMLRUNPARAM=s=4M,o=10,a=2` with the bounded dependency cache, no forced
compaction, and the unchanged 2.75 GiB cap. The final strengthened dependency
tests (warming the negative answers immediately before append/replacement)
also passed; see `constant_deps.final.log`.
That retry also finished checking 60,324 entries but exceeded the 2.75 GiB
cap during saving (exit 137). Its last sampled RSS was 2,140,272 KiB.

The next retry (`CslibV2To6000000.bounded-gc10-3g.*.log`) keeps GC `o=10` and
raises the hard cap by 256 MiB, to 3 GiB. Admission was checked with about
24.5 GiB system `MemAvailable`; the 13.5 GiB reserve, zero swap, and single-worker
restriction remain unchanged. No other application needs to be stopped.
This retry succeeded and atomically saved `CslibV2To6000000.vo`: 60,324 entries,
with a cgroup peak of exactly 3,145,728 KiB. The last sampled system reserve
was 22,867,392 KiB. The next fresh-process continuation is
`CslibV2To6500000.v` with the same runtime and guard profile.

## Next isolated declaration

The fresh 6,000,000-to-6,500,000 process successfully reloaded the checkpoint
and resumed checking, including declarations from cslib's automata library.
It then exceeded the 3 GiB cap while checking position 6,231,278,
`Std.DHashMap.Internal.Raw₀.Const.insertManyIfNewUnit_cons`. RSS rose from about
2.2 GiB to 3 GiB at that entry; this was not a saving failure. The cgroup-local
OOM at 12:46:34 on 2026-09-05 left the 6,000,000 checkpoint unchanged. Logs:
`CslibV2To6500000.bounded-gc10-3g.*.log`.

`CslibV2To6231278.v` stops immediately before this declaration;
`CslibV2Blocker6231278.v` checks only `[6231278,6231279)`. The pre-blocker build
uses a 3.25 GiB hard cap (256 MiB additional serialization headroom), GC `o=10`,
the same 13.5 GiB reserve, and the same single-worker guard. Its logs are
`CslibV2To6231278.bounded-gc10-325g.*.log`.
The pre-blocker checkpoint succeeded with 61,533 entries and a cgroup peak of
3,379,464 KiB (below its 3,407,872 KiB hard cap). The isolated checking probe
uses a 3 GiB cap, a 180-second external timeout, and a 128 MiB per-file write
limit. Its shallow conversion-entry diagnostic is in
`CslibV2Blocker6231278.entries-3g.run.log`; supervisor output is retained
alongside it.
The isolated probe reached the 180-second timeout (exit 124, peak 2,850,352 KiB)
inside conversion call 224, comparing an equality type with an applied lambda.
No checkpoint was produced. A second, 120-second diagnostic traces only that
call (`CslibV2Blocker6231278.trace224-3g.*.log`) under the same 3 GiB cap and
128 MiB file limit. The source lemma is a symbolic list-loop equation in
Lean v4.29.0 `Std/Data/DHashMap/Internal/RawLemmas.lean:2037`; it is not a
large closed numeral computation. The exact conversion cause remains under
investigation.

Trying all the existing typed conversion heuristics on the first attempt did
not help: `CslibV2Blocker6231278.typed-first-3g.*.log` again timed out at call
224 after 180 seconds (peak 2,944,076 KiB). That experiment was reverted.
Another experiment prioritizes constructor/nonconstructor argument pairs
when comparing applications of the same global constant. It also timed out
at call 224 under the same profile (peak 2,968,364 KiB;
`CslibV2Blocker6231278.constructor-first-3g.*.log`). Neither experiment
establishes a fix or produces a checkpoint.

### Direct arguments before trailing eliminations

The second trace (`.constructor-trace224-3g.*.log`) shows why the initial
reordering was insufficient: it avoids comparing the recursive method at
`List_brecOn`, but then compares the accumulator after a projection in
`List_recl[arguments; projection; accumulator]` before the direct list argument.

The retained revision precompares constructor/nonconstructor pairs only in
the matched global constant's direct application frame, before trailing
eliminations. All other arguments retain their ordinary order, and successful
precomparisons are skipped only in that initial frame. Every relevant argument
is still checked, using its original lift and threading universe constraints.
The ordinary unfolding fallback is unchanged. This remains restricted to the
typed dependency-first strategy with `Kernel Conversion Dep Heuristic` set.

`CslibV2Blocker6231278.direct-first-3g.*.log` now succeeds, including atomic
checkpoint saving: 61,534 entries, peak 3,019,588 KiB under the same 3 GiB cap.
The source export and imported proof are unchanged. The worker SHA-256 is
`2cc1aaafbac9c923f7aba555b812b6acc1cb4a844f04e553dd0ca21cc7479a2b`.
The first `CslibV2To6500000.v` attempt using this fix depended on this checkpoint
and resumed at 6,231,279.
The old pre-blocker artifact remains available with SHA-256
`b4e5988f284af1a8efc633d16ea38dd9d65edf162a6a7406d6095293bf5517c2`.

Both isolated Int32 regressions pass again with this worker, including saving:
complement peak 2,665,960 KiB; projection peak 2,404,204 KiB. Their logs have
the `.direct-first` suffix. `CompactPeanoSmoke.v` also passes (peak 120,320 KiB),
including the negative checks. It is a copy of `test-suite/success/compact_peano.v`
with `BinNat` imported instead of the stale `NArith` aggregate and the dependency
heuristic enabled. This is focused smoke coverage, not a full kernel test-suite
result. The next continuation uses the existing 3.25 GiB serialization profile
and logs `CslibV2To6500000.direct-first-gc10-325g.*.log`.
That continuation completed checking all 64,510 entries through 6,500,000,
including the slow `Std.DTreeMap.Internal.Impl.getKey!_eq_getKey!ₘ` declaration
at 6,488,747. It then exceeded the cap while saving. The kernel journal at
13:45:34 on 2026-09-05 confirms a cgroup-local OOM kill; no canonical `.vo`
was promoted. This is not a new successful checkpoint.

The retry keeps the same cap and GC settings, but `CslibV2To6500000.v` now
requires 6,000,000 directly and rechecks the complete interval. Thus the two
isolated regression snapshots are not retained as canonical ancestors. Logs:
`CslibV2To6500000.direct-ancestry-gc10-325g.*.log`.
This retry also completed checking all 64,510 entries, but exceeded the same
cap during saving (exit 137; cgroup-local OOM confirmed at 13:58:44 on
2026-09-05). Near the final slow declaration, sampled RSS was 2,712,916 KiB
versus 2,890,348 KiB on the ancestry containing the two diagnostic snapshots.
The saving peak remains unresolved. No 6,500,000 `.vo` exists; the last valid
checkpoint is still `CslibV2Blocker6231278.vo`, whose digest was rechecked after
the failure. No Rocq worker remains active.

`DirectArgumentOrderSmoke.v` also passes with the new worker (peak 62,260 KiB).
It checks a list fold returning a record, a trailing projection/application,
distinct SProp arguments, local lets, and rejection of wrong accumulators and
step functions. It is structural smoke coverage, not an established old/new
performance discriminator.

## Isolated serialization probe (2026-09-05)

`CslibV2Repack6231278.v` requires the last valid regression checkpoint, forces
its packed state, and imports the empty interval `[6231279,6231279)`. It adds no
declarations but exercises state serialization and `.vo` saving in about a
minute, without rechecking the entire preceding interval. It is a sibling test
artifact, not a new canonical ancestor.

Temporary diagnostics are enabled with `LEAN_IMPORT_CHECKPOINT_STATS=1` around
importer state packing/unpacking and `ROCQ_DIAGNOSTIC_SERIALIZATION=1` around
Rocq output segments. These distinguish importer packing from later `.vo`
writing: `Done!` is printed before importer packing has even started.

The baseline repack succeeds with `s=4M,o=10,a=2` and the existing 3.25 GiB
cap (peak 3,109,988 KiB; `.baseline-gc10-325g.*.log`). A forced `Gc.full_major ()`
before packing also succeeds but does not meaningfully reduce that peak
(3,109,368 KiB; `.full-major-gc10-325g.*.log`). Heap size remains 301,036,032 words
before and after collection. The collection experiment was removed.

Using a smaller major-heap growth increment (`s=4M,o=10,i=1,a=2`) reduces
reserved heap words but not the measured peak: 3,111,236 KiB
(`.gc10-i1-325g.*.log`). This profile is not retained. Importer packing takes
about 4.3 CPU seconds on this probe; writing the `.vo` library segment takes
about 0.15 seconds. These timings alone do not locate the earlier full-pass
OOM precisely.

The next full-interval attempt uses a 4 GiB cap, unchanged GC `s=4M,o=10,a=2`,
and both diagnostic flags (`CslibV2To6500000.serialization-gc10-4g.*.log`).
This is a larger test allowance, not a demonstrated reduction in serialization
memory. Admission requires the full 4 GiB budget **plus** the unchanged 13.5 GiB
system reserve; about 24.5 GiB was already available before launch. Exactly one
Rocq worker is allowed and swap remains forbidden. No other application was
closed or required to release memory. Both unsuccessful code/runtime experiments
above were removed rather than presented as fixes.

That attempt succeeded, including atomic saving: 64,510 entries and a cgroup
peak of 3,522,756 KiB (about 3.36 GiB), above the old 3.25 GiB allowance but
below 4 GiB. All packing and `.vo` segment markers completed. The saved checkpoint
uses the direct 6,000,000 ancestry, leaving the two diagnostic snapshots as
siblings. The earlier one-entry checkpoint remains intact with SHA-256
`9286dbc0bb49883ebed525e4eca128093bd67933537d13aecd25df5a3720e072`.

Diagnostic worker SHA-256:
`5f54b36e330f371a5d29fc25cd11f265ec6a4ed03845df9b1239c8a42624fa41`.
Diagnostic importer SHA-256:
`64280c20bfd0cb259b6e7d460f5b24fea6112b28d9d507a49792d63d48f06282`.
Their additional changes only emit optional serialization diagnostics; the
unsuccessful forced collection is absent. The fresh-process continuation is
`CslibV2To7000000.v`, with logs `.serialization-gc10-4g.*.log`.

That continuation also succeeded and saved atomically: 70,336 entries
(181,668 possible instances), 1,411 universe expressions, 460,596 names, and
6,467,658 expression nodes. Peak cgroup usage was 3,634,276 KiB (about 3.47 GiB),
under the same 4 GiB cap. It reloaded the 6,500,000 checkpoint in a fresh
process and checked the entire `[6500000,7000000)` interval. The old slow
declaration `Std.DHashMap.union_insert_right_equiv_insert_union` at 6,768,590
is included. The next continuation is `CslibV2To7500000.v`, with the same limits
and diagnostic log suffix. These are export positions, not counts of theorems.

During that continuation, `Lean.Widget.MsgEmbed._sizeOf_2_eq` at 7,216,963 took
roughly nine minutes before progressing to `_sizeOf_5_eq` at 7,217,011.
Cgroup usage stayed near 2.8 GiB. The historical
`work/cslib-checkpoints/CslibTo7441971.run.out` reports 103.29 CPU seconds for
the entire `[7000000,7441971)` interval with an older kernel/runtime profile
and about 9.7 GiB peak RSS. This is a performance regression to investigate,
not evidence that the new conversion rejects this first declaration.
The continuation stopped at the overall 1,500-second deadline (exit 124), at
position 7,387,715 in `Cslib.Algorithms.Lean.TimeM.mergeSort_same_length._proof_1_2`.
This was not an import error or an OOM: peak cgroup usage was 2,922,340 KiB
(about 2.79 GiB). No 7,500,000 checkpoint was produced. The 7,000,000 artifact's
digest was rechecked and is unchanged. All the slow `MsgEmbed` declarations
mentioned above had passed before the deadline.

For a controlled investigation, first save a sibling prefix ending immediately
before 7,216,963 (`CslibV2To7216963.v`, `.prefix-gc10-4g.*.log`), then compare
its single declaration sequentially with identical
input, GC, and memory limits. Disabling only the new direct-argument prepass,
and separately only dependency-first strategy ordering, would distinguish
these heuristic changes without restoring the memory-heavy transitive cache.
Two temporary diagnostic gates are now in the kernel source:
`ROCQ_DIAGNOSTIC_NO_DIRECT_ARGUMENTS=1` disables only the direct-argument prepass;
`ROCQ_DIAGNOSTIC_NO_DEPENDENCY_FIRST=1` restores the previous strategy order,
leaving dependency handling available as the old final fallback. The guarded
single-job rebuild passed (peak 379,300 KiB); the new worker SHA-256 is
`48b1d23fab6f00bc3814ef24d20dfeb365691e904ab8749d484821f2af350a49`.
The prefix was produced with the preceding worker; no conversion semantics
changed in this diagnostic build when both gates are absent.
Both variables must be unset for the default baseline. The single-entry source
is `CslibV2Slow7216963.v`. The first comparison is the default baseline with an
180-second whole-command limit (`.baseline-180-gc10-4g.*.log`); this is intended
to reproduce the slowdown, not to wait another nine minutes for it.
It timed out (exit 124, peak 2,684,468 KiB). The last entered conversion was
call 259, typed equality-to-equality, with dependency preference enabled and
constructor relevance/projection congruence disabled. The next comparison
sets only `ROCQ_DIAGNOSTIC_NO_DIRECT_ARGUMENTS=1`, using the identical source,
checkpoint, worker, GC, memory cap, and deadline (`.no-direct-180-gc10-4g.*.log`).
That comparison also timed out (exit 124, peak 2,684,808 KiB), but reached
conversion call 260 rather than 259. This is not enough to claim a complete
fix or a measured whole-proof speedup. The next comparison leaves the direct
prepass available and sets only `ROCQ_DIAGNOSTIC_NO_DEPENDENCY_FIRST=1`
(`.no-depfirst-180-gc10-4g.*.log`).
That comparison also timed out (exit 124, peak 2,683,940 KiB), at conversion
call 268 with dependency preference disabled. Neither isolated heuristic
disable completed the proof under this deadline. Do not present either as a
fix; further timing/GC/dependency-query measurements are needed.
The next one-factor runtime comparison restores both default heuristics and
changes only `OCAMLRUNPARAM` from `s=4M,o=10,a=2` to `s=4M,o=50,a=2`
(`.baseline-180-gc50-4g.*.log`). The hard cap remains 4 GiB, with no swap and
the same 13.5 GiB reserve. This tests whether collection pressure contributes
to the slowdown; it is not a memory-limit increase or an established fix.
It also timed out (exit 124, peak 2,849,768 KiB), at conversion call 264. The
default `o=10` profile remains the reference for further measurements; no
runtime or heuristic variant above is claimed to solve the slowdown.

An additional temporary profiling build succeeded with one job and a 1.5 GiB
cap (peak 359,988 KiB). Worker SHA-256:
`9a11882f9167be1e68d558c3b0c093562e376a529e5b06867949eb691623664f`.
`ROCQ_DIAGNOSTIC_DEPENDENCY_STATS=1` enables scalar dependency-query counters
and CPU timing, plus timing of surrounding indirect-dependency searches.
Output is logarithmically sampled, with at most sixteen extra slow-query name
reports; no diagnostic table retains term pairs. Conversion-entry output also
includes CPU time and major-GC counts. The measurement uses default heuristics
and `o=10` (`.dependency-stats-180-gc10-4g.*.log`); no cache policy changed.
That run timed out (peak 2,683,848 KiB). At 131,072 measured queries it had
116,114 hits, 14,958 misses, 13 complete answer-cache clears, and 1,748,850
visited vertices. Dependency-query CPU was 67.78 seconds; the surrounding
indirect-dependency timer later reached 85.49 seconds. Conversion call 260
started at CPU 174.444. Thus these paths have a substantial measured cost,
although the timings include any GC they trigger.

The next bounded experiment changes only the answer-cache capacity from
1,024 to 16,384 entries, keeping snapshot isolation, key equality, and eviction
policy unchanged. The unit test now issues 16,385 distinct queries over its
small graph to exercise eviction at the larger bound. This is not yet a
validated performance fix; earlier discriminating regressions must be rechecked
if the isolated test improves.
The 16K worker rebuild passed (peak 360,260 KiB), SHA-256
`f902846495630bf62a481bf7d68a0a29268158f86b4b9590f77908d74e2ddd3c`.
The standalone dependency test was linked against this worktree's kernel
with `ocamlfind ocamlopt -thread -linkpkg -package threads,rocq-runtime.kernel`.
An initial link omitted threads and failed; that was corrected before running
the actual test. The rebuilt test passes, including the enlarged eviction
exercise (`constant_deps.16k.checked.log`). The isolated performance comparison
uses `.cache16k-stats-180-gc10-4g.*.log`, retaining profiling and all the baseline
runtime limits/settings.
It still exceeded 180 seconds (peak 2,684,432 KiB), reaching conversion call
262. However, at 131,072 queries, misses fell from 14,958 to 3,112, clears from
13 to zero, visited vertices from 1,748,850 to 503,275, and measured query CPU
from 67.78 to 28.16 seconds. This supports the larger bounded cache as a
performance improvement on these queries, not as a completed whole-proof
regression result. The outstanding isolated check still needs a longer
bounded deadline or further optimization.
The complete isolated check is now being run with a 900-second outer deadline
(`.cache16k-stats-900-gc10-4g.*.log`), retaining the 600-second per-entry limit
and all memory/GC limits. Only the time allowance differs from the 180-second
measurement. This lets the test establish a complete result including saving.
That complete check passed and saved atomically: 72,441 entries, CPU through
serialization about 294.7 seconds, peak cgroup usage 3,536,364 KiB (about
3.37 GiB). `CslibV2Slow7216963.vo` is a sibling regression artifact, not a
canonical ancestor. The earlier Int32 projection/complement and DHashMap
insert-many regressions are being rechecked separately with this worker
(`CslibV2Cache16k*.v`) before resuming the regular checkpoint chain.
The Int32 projection regression passed including saving (peak 2,403,972 KiB).
The Int32 complement regression also passed including saving (peak 2,666,480 KiB).
The DHashMap insert-many regression passed including saving (peak 3,224,224 KiB).
All three used the default heuristics and the 16K answer cache; no source proof
was rewritten.
The lightweight conversion-entry diagnostic now also
labels projection/dependency strategy choices. Avoid the existing
`ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL` for long runs: it retains an unbounded
table of closure pairs. The lighter `ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES=1`
does not have that table.

## Bounded shared-term dependency scan experiment

The dependency collector used a tree traversal even when a body shared the
same physical subterm many times. A fixed, per-body 4,096-slot cache now
remembers completed scans by physical identity. Slots are overwritten on
collision; this can repeat work, but cannot remove dependencies. Inserting
after children handles the simple repeated-child DAG even with colliding
shallow hashes. The cache is discarded after collecting that body's direct
edges; it does not retain subterm dependency sets or change conversion rules.
Constant-alias bodies bypass allocation altogether.

The unit test exercises a depth-22 repeated-child DAG and an unshared
2,048-node application chain, and checks the same positive/negative dependency
answers. Baseline worker `f9028464...` took 0.529774 CPU seconds on the shared
DAG; the new worker took 0.000032 seconds. Both retained 65 cache words after
collection. The unshared chain went from 0.000226 to 0.001391 seconds: physical
hashing adds overhead when nothing is shared. This is an opportunistic speedup,
not a worst-case linear-DAG guarantee or yet a cslib performance result.

An initial version allocated the table even for each constant alias, increasing
the 1,500-alias test from 0.012 to 0.078 CPU seconds and its process peak from
47,916 to 97,028 KiB. Bypassing alias bodies brings that test back to 0.017
seconds and a 49,300 KiB process peak; retained cache size remains 34,502 words.
All dependency tests pass. Logs are `constant_deps.term-before.*`,
`constant_deps.term-after.*` (before the alias fast path), and
`constant_deps.term-alias.*` (final version).

The rebuilt worker SHA-256 is
`0a59f133509fcc97a3aa3fbbe8cfd1842a93a7cf33d968123a4b51e704125c70`.
The isolated cslib recheck uses sibling `CslibV2DirectTerm7216963.v` and
`.directterm-stats-900-gc10-4g.*.log`, with the same profiling, 900-second outer
deadline, 600-second entry deadline, 4 GiB cap, and GC settings as the successful
16K-answer-cache baseline. It passed including atomic saving: 72,441 entries,
283.375 CPU seconds through serialization versus 294.725 for the baseline.
The whole-proof improvement is modest, unlike the synthetic shared-DAG case.
The recorded cgroup peak was higher, 3,978,268 KiB (about 3.79 GiB), still below
4 GiB; this is not evidence of a full-process memory reduction. Late sampled
RSS was similar (about 2.73 million KiB in both runs), while cgroup accounting
was higher in this run; the peak difference has not been fully attributed.
The new sibling `.vo` SHA-256 is
`dfee4b2a5b4250f1b63eb4581df3ac0aebcecbca42fe1127854dc1d5d573b272`.
The three earlier structural regressions also passed including saving with this
worker (`CslibV2DirectTermInt32Projection`, `CslibV2DirectTermInt32Complement`,
and `CslibV2DirectTermInsertMany`). Respective CPU times through serialization
were 34.839, 41.865, and 54.245 seconds; cgroup peaks were 2,407,400,
2,678,520, and 3,155,088 KiB. Logs use `.regression-gc10-4g.*.log`.
The additional `check_shared_binders` unit fixture also passes: shared binder
types/bodies and intervening subtrees with common shallow prefixes preserve
an independently specified set of positive/negative references. Logs are
`constant_deps.term-checked.*`; the unit process peaked at 49,536 KiB.

The canonical `7000000 7500000` retry now uses this worker and the same strict
settings, 4 GiB cap, 13.5 GiB system reserve, and GC policy. The outer deadline
is 2,700 seconds; the per-entry deadline remains 600 seconds. Conversion
profiling and both diagnostic strategy-disabling gates are explicitly unset.
Input and 7M ancestor hashes were reverified unchanged before launch. Logs:
`CslibV2To7500000.directterm-gc10-4g-2700.*.log`. It passed including atomic
saving: 75,394 entries, 921.101 CPU seconds through serialization, and a
3,619,256 KiB cgroup peak. It passed the MsgEmbed size-of equations and the
cslib merge-sort proofs where the previous whole-command deadline expired.
The 7.5M checkpoint SHA-256 is
`26bfd03cd3ee1e8b685c4269a24f687c3b3889dbffd4330b3e7e60edc52ece1c`.
The log has no reported import error or skip. The outer 2,700-second allowance
was not exhausted. This result combines the 16K answer cache and shared-term
scan change; it does not isolate their individual full-segment effects.

The next canonical continuation is `7500000 8000000`, requiring the new 7.5M
checkpoint in a fresh worker, with identical strictness and resource settings.
Logs: `CslibV2To8000000.directterm-gc10-4g-2700.*.log`. It passed including
atomic saving: 80,732 entries, 659.237 CPU seconds through serialization,
and a 3,900,028 KiB cgroup peak. The input hash was reverified unchanged after
the run, and the log has no reported import error or skip. All Rocq workers
had exited after successful saving. The 8M checkpoint SHA-256 is
`aa782fc8b7a4f67c691cfff6d8565d7afc16d9b7e0b2d586ce56ec550fdbe1d6`.

The subsequent `8000000 8500000` continuation also passed and saved atomically:
86,266 entries, 706.470 CPU seconds through serialization, and a 4,116,124 KiB
cgroup peak. Input, ancestor, worker, and importer-plugin hashes were reverified
before launch; the compiler log has no reported import error or skip.
Logs: `CslibV2To8500000.directterm-gc10-4g-2700.*.log`.

That peak leaves only 78,180 KiB below the hard cap. The next trial imports
`8500000 9000000` using `CslibV2To9000000.v` and `OCAMLRUNPARAM=s=4M,o=5,a=2`:
more frequent collection, not more permitted memory. Stack, swap prohibition,
4 GiB cap, 13.5 GiB system reserve, and 600/2,700-second deadlines are unchanged.
Logs: `CslibV2To9000000.directterm-gc5-4g-2700.*.log`. This run failed with a
cgroup-local OOM during checking, before saving; the GC change was insufficient.
During the 9M trial's initial loading, cgroup usage approached 4 GiB while RSS
was about 3 GiB. A read-only `memory.stat` sample reported 3,208,646,656 bytes
of anonymous memory and 1,072,177,152 bytes of file cache (mostly inactive).
`memory.events` reported `max 375` but zero OOM/kill events; it still reported
zero OOM/kill events at the next sample. Thus the cgroup peak includes
reclaimable file cache and is not itself a measurement of the live OCaml heap.
Do not increase the 4 GiB cap automatically if a later segment exceeds it.

## Bitvector-adder proof memory failure at 8,680,510

The 9M continuation stopped at
`Std.Tactic.BVDecide.BVExpr.bitblast.blastAdd.go_denote_eq._unary`, position
8,680,510. Unlike the initial file-cache pressure noted above, the final growth
was real anonymous memory: the kernel journal at 2026-09-05 20:15:01 reported
`CONSTRAINT_MEMCG` for `rocq-lean-import-heavy.scope` and the Rocq worker's
anonymous RSS at 4,180,372 KiB. The scope peaked at 4 GiB with zero swap.
Only scope members were killed; the guard had also reached its RSS stop limit.
The command exited 137 and no `CslibV2To9000000.vo` was promoted. The verified
8.5M checkpoint hash remained unchanged.

The next diagnostic step is a sibling pre-blocker checkpoint,
`CslibV2To8680510.v`, importing `8500000 8680510` from the canonical 8.5M
checkpoint with GC `o=5`, the same 4 GiB cap, and a 1,800-second outer deadline.
Logs: `CslibV2To8680510.prefix-gc5-4g-1800.*.log`. It passed and saved:
86,780 entries, 760.008 CPU seconds through serialization, and a 4 GiB cgroup
peak (including file cache). Exit status was zero; the checkpoint SHA-256 is
`1f568ee68b1a3d09dcae69bafa8f447d4b54740a681b0c2e10e54db61ad087a2`.
This is not a canonical ancestor unless a later verified continuation explicitly
requires it; keep the ordinary 8.5M checkpoint available for a clean retry.

The fixed input was exported by **Lean 4.27.0-rc1**, commit
`2fcce7258eeb6e324366bc25f9058293b04b7547`, with lean4export 3.1.0, from cslib
commit `02e2a23eef42925cc87a5ce2ec76e9d07fdee267`. Both the original NDJSON
metadata and `cslib.stats.json` identify this version. Source inspection or a
reproduction using Lean 4.30 would not establish the behavior of this input.
In the matching Lean source, the generated `_unary` helper belongs to the
well-founded proof `blastAdd.go_denote_eq`, in
`Std/Tactic/BVDecide/Bitblast/BVExpr/Circuit/Lemmas/Operations/Add.lean`.
It proves correctness of a symbolic bitvector-adder loop, not evaluation of one
large concrete integer.

The isolated trial `CslibV2AdderMemo1024.v` will check just position 8,680,510
using the pre-blocker checkpoint. The first planned change is the existing
`ROCQ_DIAGNOSTIC_CONVERSION_MEMO_LIMIT=1024` setting (default 32,768), with all
other conversion strategies unchanged. This is an experiment, not a diagnosed
cause or a validated fix. Do not use a zero limit to disable the cache: it
selects the default. In the original worker, detailed `CONVERSION_TRACE_CALL`
/ `CONVERSION_TRACE_FROM` diagnostics retained an unbounded table of closure
pairs, so they were kept unset; scalar `CONVERSION_ENTRIES` logging does not
retain them. The safer diagnostic worker described below changes this default.
The isolated trial additionally stops at 3.75 GiB aggregate RSS, below the
unchanged 4 GiB hard cgroup cap. This preventive diagnostic threshold is not a
claim that a stopped proof is invalid. Its logs are
`CslibV2AdderMemo1024.memo1024-gc5-4g.*.log`. The guard stopped it at
3,932,776 KiB scoped RSS (limit 3,932,160), exit 125, without promoting a `.vo`.
It remained in conversion call 799, entered at CPU 147.590 with
`typed=true relevance=false projection=false dependency=true`, comparing
`projection/2 <> projection/2`. Thus reducing this memo is not sufficient;
there is no successful cache-size fix to promote. The prepared default-memo
sibling has not been run.

The next diagnostic, `CslibV2AdderConversion799.v`, uses the existing
`ROCQ_DIAGNOSTIC_CONVERSION_CALL=799` stop to inspect only shallow heads before
that expensive comparison. The importer's previous exception handler printed
the complete failed body and type unconditionally. This could allocate heavily
even when handling a timeout; it now requires `LEAN_IMPORT_DUMP_FAILED_DEF`
selecting a Lean declaration name or input position. The original exception is
still re-raised and strict failure handling is unchanged. This is an error-path
memory safeguard, not a proof-checking optimization.

The diagnostic stopped as requested (exit 1, not verification success), before
conversion 799 at CPU 146.632. Both sides project `LT_inst1[0]` from
`instLTNat`. Their first arguments compare a `Ref` index obtained through
`FullAdderOutput` / `mkFullAdder` with a `Ref.cast`; their second arguments are
applications of `Array_size_inst1`. The complete shallow report is in
`CslibV2AdderConversion799.capture799-gc5-4g.run.log`.

Two small guarded tests (`InvalidDefinitionDiagnostic.default.*.log` and
`.optin.*.log`) check the diagnostic change using an intentionally invalid
definition with both body and type `SProp`. Both reject with the same type error
and exit 1; only explicit opt-in prints `Failed with`. Peaks were 170,068 and
157,584 KiB. The rebuilt importer plugin SHA-256 is
`64211f244726100803469a082bd6dce7f6ee4119ed056db22b610e31840d316f`.

The next one-factor trial enables the existing projection-congruence strategy
in the first typed dependency-preference attempt, via a temporary
`ROCQ_DIAGNOSTIC_PROJECTION_FIRST=1` toggle. Constructor relevance remains
disabled in that attempt; all existing guards and fallbacks remain intact.
Unset preserves the old strategy order. This is not enabled by default or
validated as a fix. The sibling source is `CslibV2AdderProjectionFirst.v`.
The guarded single-job build passed with a 483,440 KiB peak; diagnostic worker
SHA-256: `1084b2f91d1ad3acbb4fcf9eb41f976dca3d11edb41df2faf48797f7b1eb9770`.
The trial retains memo limit 1,024, GC `o=5`, 3.75 GiB preventive RSS stop,
4 GiB hard cap and strict import. Logs:
`CslibV2AdderProjectionFirst.projfirst-memo1024-gc5-4g.*.log`. This trial stayed
in call 799 (`projection=true`) from CPU 147.252; its RSS continued rising,
reaching 3,455,592 KiB in the last guard sample. We terminated only the managed
scope (exit 143) before reaching the cap, to collect a bounded trace instead.
No checkpoint was promoted. This is an interrupted experiment, not evidence
that the proof is invalid or that projection-first can never finish.

For the next profile, diagnostic pair retention now requires the separate
`ROCQ_DIAGNOSTIC_CONVERSION_TRACE_PAIRS` opt-in, which must remain unset during
memory measurements. Ordinary tracing stores only scalar counters; its sampled
stack labels are capped at 16 frames, with no full-term rendering. The always
zero `Gc.quick_stat().live_words` field was replaced by `major_collections`.
These changes do not affect actual conversion memoization or checking.
The guarded single-job build passed (360,004 KiB peak); worker SHA-256:
`74d9bbbbb9c7994445598d604b7956f198c684778c803bfa50e882efe20349ba`.
`CslibV2AdderScalarTrace.v` selects trace call 799, disables projection-first,
retains memo limit 1,024, and limits the imported declaration to 180 seconds.
It is a bounded diagnostic, not a request to finish the full proof. Logs:
`CslibV2AdderScalarTrace.scalar799-memo1024-gc5-4g.*.log`. It timed out as bounded
at the 180-second declaration deadline (exit 1), with a 3,488,692 KiB cgroup
peak. At trace step 506, the actual successful-conversion memo held only 151
records and had not been cleared; diagnostic pair tracking remained empty.
The last stage was `after right constructor-argument probe`. The following
code still includes the constructor preference's final probe and the indirect
dependency query, so the exact expensive operation is not yet established.

`CslibV2AdderDependencyStages.v` repeats the bounded profile with literal markers
after constructor preference, around each indirect query, and around term
reification / dependency scanning. No conversion computation was changed.
Build peak: 382,868 KiB; worker SHA-256:
`c1118aee9ca6225a8165290b76ed9a7cc2fec2fa9a61660002f29d8cc9fc257c`.
Logs: `CslibV2AdderDependencyStages.stages799-memo1024-gc5-4g.*.log`;
it timed out at the 180-second declaration deadline, exit 1. The final markers
were `after constructor preference`, `before left indirect dependency`, and
`before dependency reification`. There was no `after dependency reification`
or dependency scan. This locates the expensive operation in
`CClosure.term_of_process`, called by the optional unfolding heuristic, rather
than in the subsequent constant-dependency graph scan. The hard-cap cgroup
peak was 4 GiB; the run ended by its line timeout, not an OOM kill.

The next implementation replaces this optional heuristic's full reification
with a bounded conservative occurrence probe. Unsupported closure forms,
nonidentity substitutions, or an exhausted traversal budget return unknown;
only two known opposite answers can choose a dependency direction. Otherwise
the existing constructor/oracle fallback remains. This does not skip any
kernel conversion check. The planned strict one-entry replay is
`CslibV2AdderBoundedDependency.v`; it has not yet passed.

Independent review caught an aliasing issue with update frames: the old `zip`
could update a cell used by a later argument. The pure probe therefore first
rejects any update/unsupported stack frame, before accepting even a positive
witness. This preflight shares the same 1,024-visit budget. The bound applies
to syntactic traversal, not to each existing transitive dependency query.
Other callers of `term_of_process` are unchanged; this is not a general
reification-memory solution.

The reviewed preflight version builds successfully (360,536 KiB peak), worker
SHA-256 `dfcfa3ebdd52ebac3cff05289787e0f9d4ea139c1deaa60f83905dbc4161647b`.
`BoundedDependencySmoke.v` freshly checks structural record/list equations and
rejects the two intentionally invalid accumulator/step equations. It passed
including saving, peaking at 62,936 KiB. The actual one-entry cslib replay now
uses this worker with memo limit 1,024 unchanged; logs:
`CslibV2AdderBoundedDependency.bounded-memo1024-gc5-4g.*.log`. This first full
one-entry trial still exceeded the preventive RSS limit: the guard stopped it
at 3,938,924 KiB, exit 125, while call 799 was still active. No `.vo` was
promoted. Therefore the change is not sufficient, and the earlier cslib
regression replays have not been run or claimed to pass.

The 180-second bounded trace `CslibV2AdderBoundedDepTrace.v`, using the same
reviewed worker, timed out (exit 1, no promoted `.vo`). Logs:
`CslibV2AdderBoundedDepTrace.boundedtrace799-gc5-4g.*.log`.
It confirms the bounded dependency probe returns, and conversion reaches
step 511, then stalls inside the complete-application reduction probe.
Further scalar markers distinguish wrapper-result type queries, reification,
closedness, compact-dependency scanning, and full weak-head reduction.
`CslibV2AdderApplicationStages.v` tests those markers with the same 180-second
line timeout, 4 GiB hard cap, and 3.75 GiB preventive RSS threshold.

The stage-marker worker has SHA-256
`fbaf69f9a8aff4f019c5170d7549dcb197d686a41cd235cde76510753617c447`;
its serial guarded build peaked at 480,976 KiB. The replay reached step 511
and printed `before left wrapper result type`, without the matching exit.
No process reification/closedness or complete-application WHD marker followed.
After recording this, only the verified managed profiling scope was stopped
with TERM (exit 143, no `.vo` promoted; last sampled RSS 3,308,612 KiB).
Thus the remaining expensive subphase is the wrapper-result type query, not
yet the subsequent full weak-head reduction.

A provisional follow-up gates both processes *before* those type queries.
It conservatively establishes de Bruijn closedness and a compact-operation
dependency witness within 1,024 syntactic visits, without quotation. Unknown
closures, nonidentity term substitutions, update/unsupported stack frames,
free relative variables, and exhausted fuel decline the optional strategy.
Finding a dependency witness never skips the remaining closedness checks.
Registered compact-operation pairs take their existing direct path first.
Independent read-only review found no blocking defect; full type reduction
for admitted processes remains unbounded. The unchanged declaration is tested
by `CslibV2AdderBoundedEligibility.v`; no success is claimed until that replay
and the previous regressions have completed.

This prototype built with worker SHA-256
`b514a3561bff4f8dde9537801f4701fa693477469d5fc35875f1891906226099`
(480,064 KiB guarded build peak). `BoundedEligibilitySmoke.v` passed including
saving and both negative controls, peaking at 66,608 KiB. The actual one-entry
replay uses memo limit 1,024, scalar trace call 799 without pair retention,
600 seconds per declaration and 900 seconds overall. Logs:
`CslibV2AdderBoundedEligibility.boundedeligibility799-gc5-4g.*.log`.

**This one-entry replay passed, including atomic checkpoint promotion** (exit
0, 273.329 CPU seconds through serialization). It now reports 86,781 entries,
227,021 possible instances and 8,027,333 expression nodes: exactly one more
entry than the pre-blocker checkpoint. Its cgroup peak reached the 4 GiB hard
cap, including reclaimable file cache, without a guard stop or OOM. Last
sampled RSS during saving was 3,482,832 KiB. This is a local success with the
experimental kernel, not yet a complete 9M/full-library or regression result.
The cache limit 1,024 is not established as necessary; a default-capacity
control is prepared as `CslibV2AdderDefaultMemo.v`.

The saved success has SHA-256
`cb62f43ebb5bb31d631c67da26bf7fc47bbc2fd942032e8ceebe81663cb83a11`.
The pre-blocker ancestor hash remains unchanged. A small standalone arithmetic
regression, `BoundedEligibilityArithmetic.v`, also passed with this worker:
`2^80 = 2 * 2^79` through both directly registered operations and signed-natural
wrappers, plus rejection of the corresponding false equalities. It avoids
the separately stale aggregate `NArith.vo`; 0.227 CPU seconds through saving,
73,992 KiB peak. This supplements, not replaces, actual cslib regressions.

The same worker also passed the default 32,768-entry memo control, including
atomic saving (`CslibV2AdderDefaultMemo.vo`, SHA-256
`d3b01ca1f302dfb3c5e27ec4d87976075f0505b65587b5da8779143cb659d4cd`).
It checked the same 86,781 entries and used 174.930 CPU seconds through
serialization. Call 799 took 14.145 CPU seconds, compared with 95.362 for the
1,024-entry trial. This establishes that the reduced cache is unnecessary
for this success; use the existing default going forward. The hard 4 GiB and
preventive 3.75 GiB RSS limits, zero swap and 13.5 GiB reserve were unchanged.
Logs: `CslibV2AdderDefaultMemo.defaultmemo799-gc5-4g.*.log`.

**Regression found:** `CslibV2BoundedDepInt32Projection.v` failed at 5,402,976
(`Int32.toInt_lt`) with `Stack overflow`, despite the same 256 MiB stack and
default memo capacity. The guard recorded exit 1 and 2,119,492 KiB peak; this
was not OOM, and no checkpoint was promoted. Other older regressions have not
yet run. Scalar rejection diagnostics (worker SHA-256
`d139738653761953e5d1df868a23b864cc12147343a6c2daa2c055433b261bfc`)
show the new eligibility gate rejects update frames throughout the early
relevant probes. Rejecting every update is too conservative to preserve the
needed arithmetic path; the prototype must be refined before continuation.
Logs: `CslibV2Int32EligibilityTrace.eligibility217-gc5-4g.*.log`.

A narrow follow-up allows distinct update targets only when none aliases any
visited closure. Target collection finishes before inspection, and the full
scan still checks every argument after finding a compact witness. The probe
does not mutate closures; the indirect dependency probe is unchanged. Review
passed. Worker SHA-256:
`8bf682282fa2c06159cb74c286d0b5ff8a1e3ecdeede8d0d2b069926a7a907d6`
(361,992 KiB build peak). `CslibV2Int32NonaliasUpdates.v` then passed the update
gate but still rejected ordinary lambda closures. This is not yet a recovered
regression; identity-substitution lambda support is being examined next.

Identity-term-substitution lambdas are now inspected directly: domain types
at their increasing binder depths, then the body under the stored binder
count, with bounded traversal and a domain-count check. Nonidentity lambda
substitutions still decline. Independent review passed. Worker SHA-256
`07547e3da75258a7b3c1ff8934d8233fd26e03debb50b906565be27ee3a68709`
built at 360,136 KiB peak. **The actual Int32 projection regression recovered:**
`CslibV2Int32LambdaEligibility.v` passed and saved, 34.547 CPU seconds through
serialization, 2,404,976 KiB peak. This is comparable to its earlier 34.839 CPU
second baseline. Remaining regressions and an adder replay with this updated
worker are still required; do not yet start the regular 9M continuation.

The complement regression at 5,534,591 (`Int32.toBitVec_not`) instead slowed
far beyond its earlier 41.865 CPU second baseline. Its worker was stopped
deliberately (exit 143, last sampled RSS 3,461,000 KiB), before the unchanged
preventive threshold; this does not establish a type error or a timeout.
A scalar dependency trace used worker SHA-256
`4c515eb4c0a987a4a82823b1cb01240255beea94608dc857972807d4d6c2f36c`
(360,416 KiB build peak). At conversion call 216, step 10, both dependency
queries returned unknown solely because of update frames. The right side then
unfolded `BitVec.not`, XOR, and `Nat.bitwise`, while `Int32.toBitVec` remained
on the left. The closedness gate correctly rejected this open expression.
The trace was stopped after capturing this (exit 143). This identifies lost
dependency-order information, not a need to admit more closed arithmetic.
A two-pass nonalias update check for the indirect probe is being reviewed;
its early positive dependency result must only be allowed after a complete
alias preflight. All passes must share the existing 1,024-visit budget.

The indirect nonalias-update implementation was independently reviewed and
built (worker `a9462e9f9851c80d536349f360deb595599ebf0798ee97c66eb685aa5e9249a3`,
362,424 KiB peak). `CslibV2ComplementNonaliasDependency.v` then confirmed the
next rejection was `closure:lambda` on both sides at step 10. It was stopped
after recording this (exit 143, no promoted checkpoint). Identity lambdas are
now supported in the indirect probe too: the alias pass skips their raw
payloads, while the constant pass scans domains and body with the same fuel
and early witness behavior; no closedness restriction is introduced.
This reviewed version built as worker
`239ec13ec07713f0b8781711fb72ac615607140d725eb38a6d09cca6a84ab5d6`
(360,540 KiB build peak). The current replay is
`CslibV2ComplementLambdaDependency.lambdadep216-gc5-4g.*.log`.

**The complement regression recovered:** exit 0 and atomic promotion, 42.158
CPU seconds through serialization, 2,678,724 KiB peak. At step 10, the left
dependency query now finds its witness and the right completes with false,
restoring the intended unfolding direction without expanding bitvector XOR.
The next checks use this same worker for the Int32 projection replay, the
remaining insertion/message regressions and the adder, before continuation.

With that same final probe worker, the Int32 projection replay passed again
(`CslibV2BoundedDepInt32Projection.vo`, 38.637 CPU seconds through saving,
2,413,728 KiB peak), and the insertion regression at 6,231,278 passed
(`CslibV2BoundedDepInsertMany.vo`, 51.500 CPU seconds, 3,626,236 KiB peak).
Both retained the 4 GiB hard cap and 3.75 GiB preventive RSS threshold.
Their logs use the stem `finalprobes-defaultmemo-gc5-4g`.

The message regression at 7,216,963 also passed and saved with this worker:
`CslibV2BoundedDepMsgEmbed.vo`, SHA-256
`567ae2e778982f3da261cc1d157739f332660f0e02cffb16cbcfbfac4907d1e5`.
It used 367.725 CPU seconds through serialization; the cgroup peak reached
4 GiB including file cache, with no guard stop/OOM and about 2.6 GiB sampled
RSS during conversion. This is slower than the earlier 283.375-second run;
the GC setting also changed from `o=10` to `o=5`, so this is not a controlled
measurement of the probe changes alone. Both final small regressions
(`FinalBoundedProbesSmoke.v`, `FinalBoundedProbesArithmetic.v`) passed,
including their intentionally false-equation controls. The final adder
replay with this worker, `CslibV2AdderLambdaEligibility.v`, also passed and
saved: 202.331 CPU seconds through serialization, last sampled RSS 3,283,552
KiB, cgroup peak 4 GiB including reclaimable file cache, exit zero. Its `.vo`
SHA-256 is `9cbf9a6bb5eca87df3a0dd2b1db13bfdd571b8c310b05147a65bdf6c138910a2`.
Logs: `CslibV2AdderLambdaEligibility.lambda799-gc5-4g.*.log`.
This completes the targeted regression set for worker
`239ec13ec07713f0b8781711fb72ac615607140d725eb38a6d09cca6a84ab5d6`;
it is not yet a complete 9M or full-library result.

## Next frontier: 8,940,683

`CslibV2To9000000.boundedprobes-gc5-4g.run.log` records the former adder blocker
and the later division-step theorem at 8,765,150 passing unchanged. It then
fails at 8,940,683 with `Lean import line timed out.` (600 seconds):

```text
Std.Tactic.BVDecide.BVExpr.bitblast.goCache_Inv_of_Inv._mutual
#HINT_OPAQUE 567875 8219074 8283283
```

The matching guard log records status 1, no promotion, cgroup peak 4 GiB
including file cache, and peak sampled aggregate RSS 3,452,848 KiB. This is
not a memory-guard stop/OOM, a typing counterexample, or a full 9M success.
The actual reason for the slow declaration check has not yet been identified.

Source inspection shows that this exported `_mutual` helper covers four
theorems, not only the short first proof: `goCache_Inv_of_Inv`,
`go_Inv_of_Inv`, `goCache_denote_eq`, and `go_denote_eq` in Lean 4.27's
`Std/Tactic/BVDecide/Bitblast/BVExpr/Circuit/Lemmas/Expr.lean:162–499`.
They use lexicographic well-founded recursion over expression/graph sizes
and width/bit indices. The underlying implementation returns a graph-indexed
vector and cache through nested dependent records. These are features to
preserve initially when minimizing, not trace-proven explanations for the
timeout. This is not a concrete giant numeric division.

The prefix now saved with the chunked index below. Next: use the one-entry
`CslibV2Blocker8940683.v` with scalar diagnostics and a 180-second diagnostic
timeout. Both retain the same 4 GiB hard cap, 3.75 GiB RSS threshold, 13.5 GiB
reserve, and no swap. Do not launch the prepared 9.5M continuation before a
successful 9M checkpoint exists.

The prepared diagnostic enables `ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES=1` and
`LEAN_IMPORT_DECLARE_TRACE_LINE=8940683`, with an outer 900-second timeout.
It retains the default memo size, disables full failed-definition printing,
and leaves `ROCQ_DIAGNOSTIC_CONVERSION_TRACE_PAIRS` unset. First locate the
costly conversion call from scalar entries; only then enable a selected
call trace. No diagnostic may overlap the prefix run.

The first prefix attempt checked all 87,362 entries (227,736 possible
instances), with 568,435 names and 8,283,284 expression nodes, then failed
while packing. Its last trace was `before pack cpu=761.157
heap_words=469647872 major_collections=156`. The kernel journal at
2026-09-05 23:36:59 +02:00 confirms `CONSTRAINT_MEMCG` in the managed scope,
not global OOM; the worker had 4,183,620 KiB anonymous RSS at the kill.
Exit 137, no `.vo` promotion. Logs: `CslibV2To8940683.prefix-gc5-4g-1800.*.log`.

The next controlled change calls `Gc.compact ()` at the completed-import
checkpoint boundary, before the unchanged `Marshal.to_string state []`.
It changes neither the V2 format, sharing flags, digest, nor proof checking.
Small save/resume/reload checks passed in separate processes, including a
false-equation rejection; their files are `CheckpointCompactBase.v`,
`CheckpointCompactResume.v`, and `CheckpointCompactReload.v`. The initial
resume fixture needed its equality symbols qualified as `Logic.eq` and
`Logic.eq_refl` to avoid Lean's shadowing; those initial fixture failures
were not serialization regressions. Plugin SHA-256:
`3eb33b5e6a721cf6551eae2a8ddd311591be9a981b197bb6e6a379f1a1bd3bf6`.
The actual prefix replay, `CslibV2To8940683.compactpack-gc5-4g-1800.*.log`,
again verified the prefix. Compaction reduced the major heap from
469,647,872 to 415,977,984 words (about 409.47 MiB), taking 18.564 CPU
seconds. Packing then hit the preventive RSS limit at 3,945,212 KiB;
exit 125, no `after pack`, no `.vo` promotion. GC alone was insufficient.

The installed OCaml 4.14.2 runtime's `Marshal.to_channel` is not streaming:
it builds output blocks before writing them. It could remove their overlap
with the final OCaml string, but not all serialization overhead.

The next controlled variant keeps compaction, marshals to a binary temporary
file, closes the output channel, then reads one exact-sized string. V2 format,
sharing flags, checksum, reader and proof checking remain unchanged. Ordinary
failure paths close both channels and unlink the file without masking the
original error. The atomic runner supplies its owned staging directory via
`LEAN_IMPORT_CHECKPOINT_TMP_DIR`, so it also cleans scratch files after a
worker kill. This variant did not change the snapshot format.

Small `CheckpointFileBase`, `CheckpointFileResume`, and `CheckpointFileReload`
checks all passed, including the false-equation control. A separate worker
with a one-byte file-size limit and ignored SIGXFSZ failed during packing
with `System error: "File too large"`; its wrapper confirmed zero remaining
scratch files before runner cleanup, and no `.vo` was promoted. This uses
`CheckpointFileTempFailure.v` (compiler log `.run.log`, guard `.retry.guard.log`).
An earlier wrapper invocation was refused before launching because its Bash
`-o` option collided with the runner's protected output flag; the tested wrapper
instead sets pipefail inside its script.

File-backed plugin SHA-256:
`cdebc7d83b9e89f6a75f836387fbe93979e02d1e3575b66399f7bc42a89727ed`.
The actual bounded replay is `CslibV2To8940683.filepack-gc5-4g-1800.*.log`.
That replay again checked the entire prefix, then stopped at aggregate RSS
3,952,088 KiB (preventive limit 3,932,160 KiB, exit 125). It reached
`before pack` at 778.506 CPU seconds after compaction, but never
`after checkpoint file write`. No `.vo` was promoted. Moving the output to a
file is therefore insufficient; the common Marshal traversal still allocates
its sharing table and output buffers.

### Chunked parser index (large replay passed)

`LeanParse.RRange` now stores sealed, immutable arrays of 256 references in a
persistent `Range` directory, with a short persistent tail. This removes most
per-expression index tree nodes without rebuilding the expression graph or
changing the proofs. The expected index-only saving is about 16 bytes per
element; actual whole-process savings must be measured.

The V2 object tag/envelope remain unchanged, but new payloads use
`state_format = 2`. Format 1 and the legacy unversioned 7/14-field tuples use
explicit old parser types and migrate their indices before installing state.
Existing `.vo` ancestors are not rewritten. The old reader cannot load format 2.

The first chunked plugin build passed (114,580 KiB peak under the 1.5 GiB
build cap). SHA-256:
`757bfc41c977d922f60bfdef0a9711f109544b3c730be2a3d4b913b6710299c7`.
`CheckpointChunkResume` passed: a fresh Rocq process reads the existing
format-1 `CheckpointFileBase.vo`, continues importing, and saves format 2.
`CheckpointChunkReload` then passed in another process, with positive and
false-equation controls (qualified retry logs). The first reload attempt had
already restored/saved state, but its assertion used an unqualified ancestor
name; it exited 1 and did not publish a `.vo`. Test peaks were 163,500 and
164,068 KiB. Dedicated legacy unversioned 7/14-tuple fixtures have not been run.

The standalone `test_chunked_parse.ml` passed using `run-chunked-parse-test.sh`
under the same 1.5 GiB cap (277,380 KiB peak). It checks all three indexes over
IDs 0..600, independent append branches/restoration at 255/256/257 and
511/512/513, old-layout migration, and preservation of physical AST aliases
both inside the graph and to an external declaration body. Its first build
attempt tried to link the packed plugin directly and failed with a module-type
mismatch; the tested wrapper instead compiles the actual parser sources as
standalone modules, without changing those sources.

The large replay uses `CslibV2To8940683.chunked-gc5-4g-1800.*.log` and the
unchanged 4 GiB hard cap / 3.75 GiB preventive RSS / 13.5 GiB system reserve.
The large process has loaded and migrated the 8,680,510 checkpoint:
`after unpack cpu=64.381 heap_words=408389120`, under the unchanged caps.
The complete prefix and atomic save passed, exit 0, at 765.309 CPU seconds.
After compaction the heap was 395,865,600 words, about 153.4 MiB smaller than
the failed file-backed attempt at the same frontier. Both `after checkpoint
file write` and `after pack` completed. The cgroup peak reached its 4 GiB cap
(including file cache), without an OOM or preventive RSS stop.

Saved SHA-256:
`3eeb3b9002d6debd5df0cbf42aab29ebc6ee2f2131d6cffb5c59c554c2b9b2a1`.
The read-only `inspect_checkpoint_blob.py` validates its segment/blob MD5,
envelope and Marshal header using buffers of at most 64 KiB. The format-2 blob
contains 11,843,150 Marshal objects in 98,704,306 bytes. For comparison, the
earlier format-1 checkpoint at 8,680,510 contains 20,098,010 objects in
105,037,663 bytes; these are different frontiers, not an exact paired benchmark.
Both still cross the same last sharing-table growth threshold. The measured
success does not establish that all 22.8M input lines will fit in 4 GiB.

The fresh one-entry diagnostic timed out at 180 seconds (exit 1):
`CslibV2Blocker8940683.entries-chunked-gc5-4g-180.*.log`.
It restored the new checkpoint successfully. Its conversion entries 216..230
belong to completed lazy dependency declarations (`go.match_9`, `go.match_15`);
the main declaration did not finish. This does not yet identify the expensive
operation or establish that kernel conversion is the cause.

The next diagnostic adds generic CPU/heap stage markers to the existing
`LEAN_IMPORT_DECLARE_TRACE_LINE` selection, replacing an older hard-coded
declaration-stage selector. It also enables the existing periodic translation
counters, without full term dumps. The plugin build passed (117,004 KiB peak),
SHA-256 `b798fc9296e69fc37dcbbc7401bfd7723f3ca97c3f53cd1384ade174d8de9789`.
`CheckpointStageSmoke.v` passed all stage markers, saving, and its false-equation
control (165,404 KiB peak). The stage diagnostic
`CslibV2Blocker8940683.translation-stages-gc5-4g-180.*.log` timed out in the
main body's translation: its type took about 0.006 CPU seconds; all observed
lazy dependencies finished; the main `after body`/`before quickdef` markers
never appeared. The last counters were 380,000 translation calls, 173,733
misses and 292 canonical contexts. Peak cgroup memory was 3,420,852 KiB.

The next diagnostic samples hash-table bucket statistics every 32,768
translation calls (`LEAN_IMPORT_TRANSLATION_BUCKETS`), printing scalar counts
only. Its build passed (110,268 KiB peak), plugin SHA-256:
`67a69160ee14a909c2ef138f42a2ef69ef87627d0489d17fadde9e49876a1a07`.
Current logs: `CslibV2Blocker8940683.translation-buckets-gc5-4g-180.*.log`.

### Translation context cache (real regression pending)

The bucket diagnostic also timed out. Its main translation cache was well
distributed (maximum chain around 16 at 97,345 bindings). A follow-up added
the previously unreported physical-context table and exposed the problem:
5,000/8,062/11,666 bindings all occupied a single bucket. `hash_param 1 1`
only hashes the record header; every `Environ.rel_context_val` has the same
header. Logs: `CslibV2Blocker8940683.physical-context-buckets-gc5-4g-180.*.log`.
That diagnostic was deliberately stopped after the measurements (owned scope
only, TERM, exit 143); it was not an additional timeout or OOM.

The importer now carries the canonical context IDs alongside the local
environment through recursive translation, extending both together under a
binder. The physical-context table is removed. External translation entry
points reconstruct their canonical context once; the existing interning,
cache keys, and proof translation remain otherwise unchanged. No kernel
source or checkpoint schema changed for this fix.

Build passed (112,016 KiB peak); plugin SHA-256:
`c259460e55ac80969b526d94d9a1255e9bcf780bb4a7ca021e8a9c2a04dcb003`.
Three small regressions passed with `LEAN_IMPORT_VALIDATE_TRANSLATION_CACHE=1`
(cache hits compared to fresh translation):
`TranslationContextProjections`, `TranslationContextUniverses`, and
`TranslationContextNested`, including negative controls and atomic saving.
Their peaks were 163,188 / 163,776 / 163,564 KiB. The first projection fixture
assertion used an obsolete generated projection name and failed after import;
the corrected test checks the exported property (whose type uses `val0`) and
rejects using it as a natural number. This was a test-name error, not an import
failure.

The same real one-entry regression still timed out in body translation with
the unchanged 180-second declaration limit and memory caps:
`CslibV2Blocker8940683.threaded-context-gc5-4g-180.*.log`.
It reached 472,000 calls (216,895 misses), versus about 380,000 before removing
the physical-context lookup. This is a tested partial improvement, not a
complete fix for the declaration. No blocker `.vo` was promoted.

The next diagnostic times context substitution/lookup, binder relevance, and
projection typing/reduction. It prints only operations taking at least 0.01
CPU seconds and their major-GC count, including an interrupted operation.
It does not print terms or change proof checking.
This diagnostic build passed (111,164 KiB peak), plugin SHA-256:
`9c39f784a0e216fd1d566ba986bb95c09291ae36124562095adb615728ce4673`.
Current logs: `CslibV2Blocker8940683.operation-timings-gc5-4g-180.*.log`.
This run timed out in body translation too (exit 1, no `.vo` promotion;
peak cgroup 3,221,044 KiB). Recorded operations lasting at least 0.01 CPU
seconds accounted for 145.136 seconds of context lookups (116 calls,
maximum 3.716 seconds), 10.363 seconds of context substitutions (3 calls),
and 3.468 seconds of annotation computation (2 calls). These are partial
timing totals, not complete CPU accounting. Repeated multi-second context
lookups occurred with no major collection during those individual calls.

The next investigation was `ContextCache.declaration_equal`, which calls
`Constr.equal` on normalized types/bodies. That equality recursively compares
subterms but does not memoize already-compared shared pairs.

### Bounded syntactic DAG equality (September 6)

The importer-local `LeanConstr.equal` now delegates structural decisions to
`Constr.compare_head` (the same comparator used by `Constr.equal`), including
its evar-argument comparison. It remembers only *completed equal* physical
subterm pairs, with the argument count. The direct-mapped table has 4,096 slots,
is allocated only after 64 non-physical comparisons, and dies at the end of
each equality call. Collisions discard cached results, never authorize an
equality; lookup cost stays bounded even for identically hashed deep terms.
Only the translation-context interning cache uses this helper. There is no
kernel change, reduction shortcut, new axiom, or declaration-specific rewrite.

`run-constr-equal-test.sh` passed against the actual Rocq `Constr.equal`:
alpha/casts, different indices/sorts/universe instances, evars including sparse
arguments, fix/cofix, arrays, 500 generated pairs plus independently copied
terms, and shared-DAG positive/late-negative cases. The depth-20 paired oracle
test took 0.184 CPU seconds; the depth-45 memoized positive and late-negative
tests together took 0.000149 seconds (the latter deliberately do not run the
exponential oracle). Peak for build/link/test was 267,908 KiB under 1.5 GiB.
Log: `constr-equal-test.log`.

Plugin build passed (115,260 KiB peak), SHA-256:
`027eb96b2260e0df081ee798b1fbfb5c9a3555c92fc88f0c990c0dda690424ae`.
The worker remains `239ec13e...`. All three translation regressions passed
again with cached-versus-fresh validation and negative controls, under the
same 1.5 GiB cap. Logs: `TranslationContext{Projections,Universes,Nested}`
with `.dag-equality.*.log` (the projection compiler log omits `.property`).
The real one-entry 180-second diagnostic failed with unchanged caps:
`CslibV2Blocker8940683.dag-equality-gc5-4g-180.*.log`.
It reached only 409,000 calls versus 470,000 with ordinary equality; equality
memoization alone is not a fix and regresses this case. Exit 1, cgroup peak
3,218,788 KiB; no `.vo` was promoted.

The context-key substitution itself uses `Vars.substl`, which rebuilds each
occurrence of an open shared subterm separately. A targeted test confirms that
the resulting tree loses physical child sharing. `LeanConstr.abstract_context`
now performs the same substitution of canonical Meta IDs, using
`Constr.map_with_binders` and a bounded 4,096-slot physical-term/binder-depth
memo. This only affects internal cache keys, not imported terms. Its semantics
were compared against `Vars.substl` for 500 generated terms with three contexts,
fix/cofix, variable shifts, and a shared term occurring at different depths.
Positive/negative depth-45 DAG normalization/comparison completes in 0.000515
CPU seconds. Log: `constr-equal-abstraction-test.retry.log` (232,356 KiB peak).
The first sharing assertion exposed that ancestors starting before lazy-table
allocation did not save their result; insertion now uses the current table.
All equality/substitution result checks passed even in that first test; the
failed assertion was specifically about preserving sharing.
The combined plugin build passed (111,428 KiB peak), SHA-256:
`1b41dbfad7e39b4767dd3796cb98511cc944f4d27df30fdd22fadf429c5df9cf`.
All three cached-versus-fresh translation regressions passed again, including
negative controls and atomic saving (`TranslationContext*.dag-context.*.log`;
peaks 163,676 / 163,836 / 163,736 KiB). The fixed input SHA-256 was verified
again unchanged before the next real run.
The combined one-entry diagnostic still timed out:
`CslibV2Blocker8940683.dag-context-gc5-4g-180.*.log`, with unchanged caps and
180-second per-declaration timeout. It reached 533,000 translation calls,
versus 470,000 before either DAG change; no `.vo` was promoted. Recorded slow
context lookups totalled 133.030 CPU seconds, but this was not all comparator
work (see the GC diagnostic below).

### Incremental-GC debt after checkpoint loading

`CslibV2Blocker8940683GcTrace.v` uses a short 30-second declaration limit and
the same plugin/caps, with `OCAMLRUNPARAM=...,v=64` to expose runtime GC slices.
It deliberately times out; logs are `CslibV2Blocker8940683.gc-slices-gc5-4g-30.*`.
Repeated 3.3-second context lookups are bracketed by major-GC marking slices
of 646,132,765 words and an outstanding work backlog around 135 (printed in
millionths as `135856463u`). A major cycle need not *finish* during a slice,
so `major_collections=0` in the earlier timing records did **not** exclude GC.
The earlier attribution of all that time to structural comparison was too
strong. Peak cgroup was 3,454,700 KiB; exit 1 was the expected line timeout.

OCaml 4.14.2's `runtime/major_gc.c` carries this backlog after bulk allocation;
`caml_finish_major_cycle` resets it when starting a full cycle from idle.
`Gc.full_major` completes the current cycle and runs another. The new minimal
candidate calls this once after a packed importer state has been restored,
before declaration translation; it does not change any memory cap or proof.
The ordinary `Constr.equal` and `Vars.substl` context operations are restored.
The DAG prototype is retained only in `dag-context-experiment/` with its tests,
and is no longer linked into the importer. The minimal plugin was rebuilt
explicitly with `make -f Makefile.rocq -W src/lean.ml ...` because removing a
module from `.mlpack` alone did not invalidate the old packed binary.
Build passed (111,072 KiB peak), SHA-256:
`813093dcef9962317260926da1ecf6a079bf133ef154e2cfe2e93859269fc44e`.
`ocamlobjinfo` confirms the prototype is absent from the rebuilt pack.

`CheckpointChunkReload` passed with positive/negative controls and atomic
saving (`.post-unpack-gc.*.log`, 163,648 KiB peak). It exercises a format-2
reload in a fresh process; the new GC boundary completed in 0.440 CPU seconds.
The real 180-second diagnostic failed with this build and ordinary context
operations: `CslibV2Blocker8940683.postload-gc5-4g-180.*.log` (exit 1, no `.vo`,
peak 3,218,816 KiB). The GC backlog was **not cleared**. The trace shows pending
actions starting another incremental cycle between the two full cycles, so
`caml_finish_major_cycle` never enters the idle branch that resets its backlog.
Disassembly of the actual worker confirms that the reset is conditional on
that branch; this is not merely an assumption from another runtime's source.
The ineffective extra `Gc.full_major` call was removed. No OCaml runtime,
global toolchain, memory limit, or kernel modification was made.

The normal-limit check restored the original plugin bit-for-bit:
`9c39f784a0e216fd1d566ba986bb95c09291ae36124562095adb615728ce4673`
(build peak 110,816 KiB). It used the full pass's normal 600-second declaration
limit in `CslibV2Blocker8940683FullTimeout.v`, starting from the saved numeric
8,940,683 prefix, not re-importing the earlier range. Logs:
`CslibV2Blocker8940683.normal-timeout-gc5-4g-600.*.log`.

**The declaration was accepted**, without either DAG prototype or an added GC
call. Type translation ran from CPU 66.732 to 66.738, body translation from
66.738 to 462.134, and kernel declaration checking completed at 610.253.
Thus the complete declaration took 543.521 CPU seconds (within its 600-second
limit), including 395.396 seconds in body translation and about 148.1 seconds
in declaration checking. The importer printed `Done!`, with 87,363 entries
and 227,737 possible instances. The short 180-second diagnostic limit was
insufficient for this run; it is not evidence that the normal limit fails.

**Saving still failed.** The save-stage GC began at CPU 610.267 and packing at
627.408, with `heap_words=421136384`. At 11:05:11 Paris time on September 6,
the kernel killed this test's entire managed scope at its hard 4 GiB limit
(exit 137). The last sampled RSS was 3,730,124 KiB; a subsequent burst outran
the 1-second preventive poll. Kernel journal evidence says
`constraint=CONSTRAINT_MEMCG` and names only
`rocq-lean-import-heavy.scope`; this was not a global desktop OOM.
No `.vo` was promoted. The canonical prefix hash remains
`3eeb3b9002d6debd5df0cbf42aab29ebc6ee2f2131d6cffb5c59c554c2b9b2a1`.
The scope is inactive and no Rocq worker remains. No caps were increased.

The next problem is now saving this *already-checked* state within the same
budget, not proving or translating this declaration. Do not reintroduce the
failed context/DAG or post-load `Gc.full_major` experiments. The Marshal sharing
table peak documented above remains relevant; the former successful prefix
compacted to 395,865,600 heap words, versus 421,136,384 after this declaration.
That is about 193 MiB of additional heap capacity, not a direct live-object
size measurement. No change to OCaml's runtime or the system toolchain has
been implemented or authorized by this experiment.

## Indexed parser checkpoint prototype (format 3, September 6)

The current candidate replaces the parser's expression graph *on disk* with
topologically ordered records containing expression/name/universe indices.
Entry and mutual-inductive metadata use references into that same graph;
adapted constructor fragments are separately memoized so their sharing and
their links back to parser expressions survive. The ordinary in-memory AST
and all proof translation/checking code are unchanged. Formats 1 and 2 still
decode through their existing paths; new saves use format 3 in the existing
versioned envelope. This is not a delta checkpoint or an OCaml runtime patch.

`LeanParse.Checkpoint` uses typed constructors and no `Obj` operations. A
temporary open-addressed reverse index stores integers, with its immutable
parser array owning the keys, instead of boxed hash-table entries. It streams
the encoded graph to a scoped temporary file, releases reverse indices, and
then reads the final byte string. A checkpoint GC runs before Marshal, which
now traverses metadata and the encoded bytes rather than millions of AST
objects. The reverse-index probes are measured because collisions could
still be a performance issue; a large-memory saving is not assumed yet.

`test_indexed_checkpoint.ml` passed all expression constructors, shared DAGs
across chunk boundaries, entry/parser and adapted-fragment aliases, metadata,
post-reload appends without changing old snapshots, and malformed encoded
graphs. The tests compile the actual parser sources without plugin packing.
Log: `indexed-checkpoint-unit.retry.log` (276,084 KiB peak under 1.5 GiB).
The first compile used `Option.is_some` instead of Rocq's `Option.has_some`;
that compilation error was corrected before any Rocq fixture ran.

Plugin build passed (115,848 KiB peak), SHA-256:
`77614c42bfbf7cbe13d9b6d4713eed83049b8f29c574019136fde9406763b0f6`.
The worker remains `239ec13e...`. These fresh-process tests all passed with
positive/negative controls and atomic saving under 1.5 GiB:
`CheckpointIndexedFromV1`, `CheckpointIndexedFromV2`, `CheckpointIndexedReload`,
`CheckpointIndexedPolyBase`, and `CheckpointIndexedPolyResume`.
The poly tests specifically verify that `PolyId_inst1` is absent before saving
and is successfully generated from restored source metadata after loading;
the new instance has type `forall A : SProp, A -> A`. Final poly logs use the
`.lazy-control` suffix. The blob inspector recognizes format 3 and verified
the small V1-to-V3 file's envelope/digests/header (not inner graph typing).

The first large candidate test **passed**, including atomic saving:
`CslibV3Encoding8940683.v`, logs `CslibV3Encoding8940683.{run,guard}.log`.
It reads the existing numeric 8,940,683 prefix and saves it in format 3 without
checking additional declarations. Same 4 GiB hard cap, 3.75 GiB preventive RSS
threshold, 13.5 GiB reserve, no swap; the preventive poll is now 0.25 seconds
for this run. It completed at CPU 281.315, with peak cgroup usage 4,086,068 KiB
(including file cache; not a live-heap/RSS measurement). The new `.vo` SHA-256
is `985235ac0fc894063246e56e80b2f0a1c8a635f8d263655060653a5413462a7b`.
This sibling is not an extension of the canonical frontier.

The read-only blob inspector verified format 3, envelope/digests/header:
88,721,930 bytes, 3,558,421 Marshal objects, 20,575,722 heap words on 64-bit.
The old format-2 checkpoint at the same frontier contains 11,843,150 objects.
The derived Marshal sharing-table resize peak consequently falls from 774 MiB
to 193.5 MiB (steady size 129 MiB). This is a table-allocation calculation from
the validated header and actual OCaml implementation, not sampled total RSS.
Indexed encoding itself took 174.143 CPU seconds: 109,123,117 expression-index
probes, maximum probe length 2,092. Its temporary reverse index is therefore
not constant-hash-degenerate on this input, but is not a free optimization.

`CslibV3Reload8940683.v` also **passed** in a fresh guarded process, including
re-saving, at CPU 331.665 (peak cgroup 3,834,600 KiB). Its `.vo` SHA-256 is
`d2091354ac3e0d10858bbb519466017e58d2677deeca352363a810ad7442f264`.
Decoding took 42.456 CPU seconds; indexed re-encoding took 176.787 seconds.
The resulting importer blob has the **same bytes/digest** as the first indexed
file (`46befba2073fc276d6bd4b156df25345`, 88,721,930 bytes), with the same object
count and index-probe statistics. This supplements the typed small alias and
lazy-SProp regressions with a full-size serialization roundtrip.

The canonical continuation `CslibV2To9000000.v` starts at the verified
numeric 8,940,683 prefix, with range `8940683 9000000`, avoiding an unnecessary
re-import from 8,680,510. It **passed** with the indexed plugin, 600 seconds per
declaration, 2,700 seconds overall, and unchanged memory caps (0.25-second
preventive poll). Logs: `CslibV2To9000000.indexed-gc5-4g.{run,guard}.log`.
Neither large codec diagnostic is added to this chain. The formerly slow
declaration at 8,940,683 completed in 542.129 CPU seconds; the full import
finished at CPU 670.878, and atomic saving succeeded at CPU 797.389. Peak
cgroup usage was 3,873,920 KiB. Both plugin and worker hashes were reverified
after the run; the checkpoint hash is recorded in the frontier section above.

The new blob's validated format-3 envelope contains 89,366,184 bytes, MD5
`aba15953ce02c1ed2d642b99160ed7c2`, 3,588,114 Marshal objects and 20,735,527
64-bit heap words. The derived sharing-table resize peak remains 193.5 MiB.
Indexed encoding took 85.227 CPU seconds on this run, with 110,052,165 probes
and maximum probe length 2,098. This is a real post-declaration save, not just
an unchanged-prefix serialization test.

Two further fresh-process controls passed sequentially under 1.5 GiB:
`CheckpointIndexedMutualBase` and `CheckpointIndexedMutualResume` (peak cgroup
163,964 and 164,024 KiB). They split the existing `dumps/mutual_instances` at
line 149. Both `PolyTree_inst1` and `PolyForest_inst1` must be absent before
saving, then are generated together from the restored mutual-block metadata
when importing `polyPropExample : PolyTree_inst1 True`. Wrong-type controls
are rejected in both files. No fixture overwrote its source dump. Source
inspection found name-based mutual-block lookup and structural parameter
comparison, not a requirement for physical identity of the `ind` records;
expression-DAG sharing is preserved separately by the codec.

The first canonical `9000000 9500000` continuation used the same plugin/worker,
600-second declaration limit, 2,700-second overall timeout, and unchanged
memory guards. It stopped at 9,380,048 with a missing constructor (below).
Logs:
`CslibV2To9500000.indexed-gc5-4g.{run,guard}.log`.

The strengthened standalone codec tests also passed: explicit parser alias-tag
roundtrip, out-of-range name/universe references, overflowing varint count,
and oversized string length. Log: `indexed-checkpoint-unit.alias-bounds.log`,
peak 235,004 KiB under 1.5 GiB.

## Constructor-first universe instantiation (September 6)

The 9M-to-9.5M run failed at `Lean.Server.Watchdog.eraseFileWorker`, line
9,380,048, with `missing Lean.JsonRpc.ResponseError.mk`. It exited 1, not an
OOM or timeout; peak cgroup usage was 3,413,864 KiB. No 9.5M checkpoint was
promoted. The source `ResponseError` record and its constructor were already
exported at line 7,245,252, so the constructor was not absent from the input.

`constructor-owner-repro/ConstructorOwner.lean` reproduces the same importer
failure with two tiny types and `def repro : Token := (Box.mk Token.mk).value`.
Lean 4.27.0-rc1 compiles it; its genuine export has 74 lines. The old plugin
fails at line 74 with `missing Box.mk` (`ConstructorOwnerRepro.before.*.log`).
Projection application translation processes arguments before lazily declaring
the projection instance. Thus it can request a constructor instance before any
reference has requested its parent inductive's instance. `ensure_exists`
previously consulted source entries under the constructor's name, but only the
inductive entry contains constructor metadata.

The importer now maintains a derived constructor-to-inductive name index.
On a missing constructor instance it first calls `ensure_exists` on the owning
inductive; this also selects the complete mutual block when applicable.
The ordinary inductive declaration registers its constructors. The index uses
explicit constructor metadata, not a namespace guess or library-specific name.
It participates in summary rollback and is rebuilt from source entries at
checkpoint load, so the checkpoint schema and old readers are unchanged by
this fix. No kernel or imported proof changed.

The importer build passed under 1.5 GiB (peak 110,396 KiB), SHA-256
`8c1e2aee92095f70de5c9741b4087249d227ee81991e1fbd57b20cb5547cf412`.
Five sequential tests passed with positive/negative controls and atomic saving:
`ConstructorOwnerRepro`, `ConstructorOwnerBase`, `ConstructorOwnerResume`,
`CheckpointIndexedMutualBase`, and `CheckpointIndexedMutualResume`. The base
requires `Box_inst1` to be absent before saving; the resume generates it while
checking the failing expression. Logs use `.constructor-owner`, and all peaks
are below 165,000 KiB. The two mutual tests are non-regressions, not a separate
constructor-first mutual-block reproduction.

The full `9000000 9500000` continuation ran with the constructor-owner importer
and unchanged worker, timeouts and memory caps. Logs:
`CslibV2To9500000.constructor-owner-gc5-4g.{run,guard}.log`.
The input and 9M ancestor hashes were freshly reverified before launch. The
small before/after test proves the generic fix. The actual declaration at
9,380,048 also passed, and the replay checked all the way to 9.5M without
errors or skips: 94,241 entries (246,064 possible instances), 1,722 universe
expressions, 609,643 names and 8,794,395 expression nodes. Checking finished
at CPU 845.063. Saving then exceeded the preventive RSS limit; no 9.5M `.vo`
was promoted. The canonical frontier remains 9M.

## Temporary checkpoint-index capacity cliff (September 6)

In that run, indexed encoding finished at CPU 958.112 (91.687 seconds), with
84,179,625 probes and maximum probe length 1,418. The following `Gc.compact`
did not reach the `before pack` trace: the guard stopped the owned workload
at aggregate RSS 4,018,996 KiB, above the 3,932,160 KiB preventive threshold
(exit 125). This was a preventive stop, not a successful checkpoint or a
cgroup-OOM result. The 4 GiB hard cap, 13.5 GiB reserve and no-swap setting
were unchanged.

The reverse-index allocator reserved twice the *next power of two* of the
expression count. Crossing 8,388,608 nodes therefore doubled its slot array
from 16,777,216 to 33,554,432 native integers. It now allocates exactly twice
the count (at least two slots), retaining the same maximum 50% occupancy.
Lookup uses modulo for the initial bucket and an explicit wrap at the end
of the array. Overflow checks remain; the stored checkpoint bytes, source
AST, translation and kernel are unchanged.

At 8,794,395 expressions this reduces the slot-array allocation from
268,435,456 to 140,710,320 bytes. Including names and universes, the calculated
reduction is about 128.5 MiB. This is an allocation calculation, not a measured
reduction of the complete run's peak; the real retry must establish that.

`exact-index-unit.log` passed all codec, DAG-sharing, fragment, alias and
malformed-wire controls (234,288 KiB peak under 1.5 GiB). The plugin build passed
(113,104 KiB peak), SHA-256
`c50b61ef63d06f102ad33b7a4601e11d1550667fe93e14ff229c21ae3daad175`.
Ten fresh-process tests then passed sequentially, with `.exact-index` logs:
the three constructor-owner drivers, V1/V2 migration, V3 reload, and both
base/resume pairs for polymorphic definitions and mutual blocks. The small
parser's serialized size remains 2,978 bytes.

The real `9000000 9500000` retry used this importer and the unchanged worker,
timeouts and memory settings. Logs:
`CslibV2To9500000.exact-index-gc5-4g.{run,guard}.log`.
The export, 9M ancestor and worker hashes were freshly reverified before
launch. Checking again passed (CPU 845.636), but the guard stopped saving at
4,010,804 KiB RSS during the post-encoding `Gc.compact` (exit 125). No `.vo`
was promoted. Encoding used less sampled RSS (3,645,684 versus 3,770,356 KiB)
but the major heap still grew to exactly 501,256,192 words. Encoding took
101.480 CPU seconds, 114,165,854 probes, maximum probe length 2,134.

## Post-encoding compaction peak: rejected collection experiment

A candidate added `Gc.full_major` after the temporary graph file was written
and before its final byte string was allocated. The hypothesis was that
reclaiming the now-unreachable reverse-index arrays first would avoid heap
growth. This is different from the rejected post-*unpack* backlog experiment;
neither call is now present in production.

Candidate plugin `55426e9133ca31d6423382bbb581db20553b4f2d5d55ffd51ba34faed5b4dc4c`
passed the standalone codec tests and ten fresh-process controls (`reclaim-index`
logs), but failed the large save-only test `CslibV3Save9000000Reclaim.v`.
That test requires the canonical 9M checkpoint and imports `9000000 9000000`,
so it checks no new declarations. Encoding ended at CPU 380.546 and the heap
still grew from 429,905,408 to 494,391,296 words. The runtime log reached
`Compacting heap...`, then the RSS guard stopped the workload at 3,965,232 KiB
(exit 125). No diagnostic `.vo` or 9.5M checkpoint was promoted.

The added collection call was removed, and the rebuilt plugin is byte-for-byte
the previously tested `c50b61ef...` (restore build peak 110,840 KiB).
The smaller reverse-index allocation remains: it demonstrably reduces encoding
RSS, but is not by itself a complete saving fix.

OCaml 4.14.2 source inspection shows that compaction moves live objects before
freeing empty heap chunks (`runtime/compact.c`). Both measured heap increases
match the default 15% major-heap growth step, including page rounding.
`runtime/major_gc.c:caml_clip_heap_chunk_wsz` applies percentage increments
when the configured value is at most 1000. The next diagnostic changes only
the per-run setting to `OCAMLRUNPARAM=s=4M,o=5,i=5,a=2,v=21`; it does not modify
the OCaml installation or increase any resource cap. A much earlier `i=5`
experiment at 5.5M was interrupted during checking, not demonstrated to fail
saving, so it does not decide this case.

`CslibV3Save9000000SmallGrowth.v` passed with that setting and the restored
`c50b61ef...` plugin; logs have the same basename. It used the
same 4 GiB hard cap, 3.75 GiB preventive RSS threshold, 13.5 GiB system reserve,
no swap, and a 900-second outer timeout. `v=21` enables major-GC, heap-growth
and compaction messages. The earlier `v=49` trace did **not** include heap
growth (bit 0x04); its stage counters and compaction messages are still valid.
The smaller-growth diagnostic completed at CPU 386.056 with peak cgroup usage
3,808,472 KiB (3.63 GiB), including atomic saving. Its `.vo` SHA-256 is
`0e0491ee4058859b9bfa8014a49756b68e25bf1e7be728767acdc017f70e1796`.
Heap capacity after unpack was 412,140,544 words (versus 443,842,048 with the
default increment); encoding grew it in two smaller steps to 454,385,664.
Post-encoding compaction succeeded and left 441,471,488 words before packing.

The read-only blob inspector verified the file's segment/envelope/digests.
Its format-3 importer blob is byte-identical to the canonical 9M blob:
89,366,184 bytes, MD5 `aba15953ce02c1ed2d642b99160ed7c2`, 3,588,114 objects.
This is a successful memory diagnostic, not an extension of the canonical
chain; do not add this sibling as an ancestor of the next continuation.

The full `9000000 9500000` replay **passed checking and atomic saving** with
`i=5`, the same importer and worker, 600 seconds per declaration and 2,700
seconds overall. Logs:
`CslibV2To9500000.small-growth-gc5-4g.{run,guard}.log`.
Input, 9M ancestor and worker hashes were freshly reverified before launch.
The run exited zero with peak cgroup usage 3,894,788 KiB (3.71 GiB); all memory
caps remained unchanged. The real constructor-owner regression at 9,380,048
passed again. All 94,241 entries were checked by CPU 1,022.672. Indexed encoding
ran from CPU 1,044.376 to 1,156.103; the major heap grew from 441,471,488 to
463,545,344 words. Post-encoding compaction succeeded, leaving 447,581,184
words before packing. Serialization finished at CPU 1,184.987.

The canonical `.vo` SHA-256 is
`30c1394fbe2d6eda64912244bf6a522ac1c14fb0add6dca8a59ec50973a542be`.
Read-only inspection verified its segment/envelope/digests: format 3,
94,616,124 blob bytes, MD5 `dc57ab2383801131bd9970e7646804fc`, 3,807,394
Marshal objects and 21,976,986 words on 64-bit OCaml. The 9M ancestor hash was
reverified unchanged. This is a canonical extension, unlike the save-only
diagnostic sibling. The next fresh-process continuation is `9500000 10000000`;
it must retain `i=5` and the same safety limits.

`CslibV2To10000000.v` was launched after the 9.5M producer exited and after
reverifying the export, ancestor, importer and worker hashes. It used the same
settings and a single guarded worker; logs are
`CslibV2To10000000.small-growth-gc5-4g.{run,guard}.log`.
All declarations passed: 100,822 entries (261,849 possible instances), 1,820
universe expressions, 652,657 names and 9,244,702 expression nodes, by CPU
867.580. Indexed encoding started at CPU 891.820 with 461,857,280 heap words.
Two further heap-growth steps preceded the preventive stop at aggregate RSS
3,936,956 KiB (limit 3,932,160), exit 125. No 10M `.vo` was promoted, and the
9.5M ancestor SHA-256 was reverified unchanged. This was an owned-workload
safety stop, not an observed system OOM or typing error.

## Canonical launcher safety

The tracked checker launchers now use a checker-local copy of the same memory
guard. The frontier runner guards its build/version checks as well. Builds are
serial, child statuses are preserved, and frontend cancellation reaches the
guard through `/usr/bin/time` so it can stop detached workers. The process-tree
regression failed with PID-only cancellation and passes with owned-group
cancellation; it uses tiny Python children, not actual Rocq workers.

The generated import also disables the default missing-quotient skip exception.
The frontier runner forces `Fail`, ignores inherited diagnostic ranges unless
its own range arguments are supplied, and treats reported errors/skips as
failure even if the child returns zero. The next-entry detector also recognizes
the definition-hint tags used by the fixed export. Seventeen mock-only tests pass (about
five seconds), as do shell syntax and whitespace checks. These tests cover
dispatch, cleanup, and result handling, not kernel correctness or a full arena
run. The checker guard's live refusal of a second scope was also verified during
the 7,000,000 continuation. No extra Rocq process was started for that check.

## Frontier identity audit

The canonical frontend previously probed plain `rocq --version` even when
the checker compiled with a different `ROCQLKA_ROCQ`. It now probes, propagates,
and records the same selected command. Relative path-bearing launchers are
anchored to the invocation directory without collapsing `..` across symlinks.
Each new history entry owns its input identity, and input SHA-256 is recomputed
even when size/mtime match a prior run. Log files have distinct nanosecond-based
names and are opened exclusively, avoiding same-second overwrites.

The four new mock regressions failed before these fixes (wrong probe, missing
per-run identity, stale SHA, colliding logs). Review caught a further symlink
path-normalization edge case, reproduced and fixed before the final run.
All 21 mock tests now pass, including the existing dispatch/cancellation tests;
no additional Rocq or build was launched. Logs: `frontier-identity.before.log`,
`frontier-log-identity.before.log`, `frontier-launcher-path.before.log`, and
`frontier-identity.final.log`. Shell syntax and whitespace checks also pass.

This improves reporting, not the proof of upstream compatibility. The frontend
still lacks executable/worker and loaded-artifact fingerprints; NDJSON converted
export/cache provenance is not yet content-verified. A fresh upstream-kernel
claim needs the actual clean kernel/build and importer artifacts identified,
the consumed export identified, and a full fresh check or checkpoint ancestry
entirely regenerated under that kernel. Loading experimental `.vo` files with
a stock executable is not such a check. Old history entries without per-run
input identity are not retroactively assigned one.

## Checkpoint-chain memory caveat

V2 avoids expanding every ancestor's parser graph, but each `Keep` library
object still owns a full marshalled snapshot. Rocq's loaded-library and module
object tables retain those strings even after the newest state is forced.
Consequently, packed bytes accumulate across the checkpoint ancestry; clearing
the importer's pending pointer does not release them. This was established by
source inspection. A read-only inventory of all 27 canonical ancestors through
9.5M verified their checkpoint envelopes/digests and measured 1,622,655,374
packed-state bytes (1.51 GiB), excluding Rocq declaration data. Inventory log:
`checkpoint-chain-9500000.inventory.log` (exit zero, peak cgroup 14,296 KiB under
a 1.5 GiB diagnostic cap). This measures stored payloads, not a complete
attribution of the running process's RSS.

After the 10M saving failure, the next experiment starts the entire fixed export
from an empty importer state, without requiring these checkpoint libraries.
This avoids loading their snapshots without mutating or deleting any ancestor,
changing proof checking, or adding another serialization format. It trades a
fresh recheck for lower retained checkpoint overhead. Live source terms and
Rocq declarations still grow, so fitting the complete library is unproven.
See [the fresh-run record](../cslib-full-fresh/README.md).

For future canonical checkpoints, prefer rechecking from the previous regular
checkpoint once a blocker is fixed, keeping pre-blocker and one-entry artifacts
as sibling regression tests where practical. That avoids adding two nearly
identical full snapshots to every subsequent process. Existing ancestors must
not be overwritten while their descendants remain in use. Mutating old library
object payloads to reclaim memory would violate their persistence contract.
Versioned compression or incremental snapshot formats are possible future
work; neither is implemented here. Indexed format 3 reduces serialization
overhead, but still stores a full snapshot for each ancestor.

There is also a separate live-state limit: `LeanParse.parsing_state` retains
all parsed names, universes, and expressions in append-only persistent ranges.
The importer's `entries` table retains source declaration bodies for later
universe instantiation. Removing duplicate ancestor snapshots would not remove
these live graphs or Rocq's checked environment. The 4 GiB cap has not been
shown sufficient for the complete export. Compression alone would still need
the uncompressed Marshal buffer during saving/loading; do not present it as a
bounded-memory fix without measurements.

The persistent chunked parser index now retains sealed 256-element arrays in
a `Range` directory, with a short persistent tail. This preserves undo and
dense IDs without retaining one tree wrapper per expression. Legacy-format
migration, indexed encoding and their measured tests are documented above;
none of these changes remove the live parser graph.

Removing snapshot accumulation itself needs more than compression: a versioned
delta format would store a parent identity plus new parser nodes and changed
metadata, with stable IDs for graph edges. Naively marshalling appended AST
nodes would recursively copy older graphs again. Such a format must preserve
V1/V2 loading, exact parent-chain reconstruction, undo, branching and lazy
universe instantiation. It cannot shrink existing immutable V2 ancestors or
remove the growing live parser/Rocq environment. No delta-format change has
been made; the current continuation uses full snapshots in packed format 3.

## Safe fresh full pass

The 9.5M continuation passes checking and atomic saving, but the 10M continuation
exceeds the preventive RSS limit while saving. Do not rerun it unchanged. The
command below starts the complete fixed export from the beginning, without
checkpoint ancestors, retaining `i=5` and all memory limits. It allows 600 seconds
per declaration and eight hours overall; only the overall time allowance changes
for this much longer run. Preserve all canonical ancestors.
This is not a full-library result. Do not run this command if a full pass or
continuation is already active; inspect its existing compiler and guard logs.

Use the indexed importer build identified in the frontier section; older
readers cannot load format 3. If kernel sources have changed, rebuild the worker
with one build job using the first command below. Do not rebuild needlessly
while an import is running. The build is capped at 1.5 GiB and preserves at
least 13.5 GiB of system memory:

```sh
repo=/home/theo/Documents/github/rocq-lean-typechecker
cd "$repo/_worktrees/rocq/compact-peano-view"
ROCQ_MAX_RSS_KIB=1572864 \
ROCQ_MEMORY_MAX_KIB=1572864 \
ROCQ_MEMORY_HIGH_KIB=1572864 \
ROCQ_MIN_AVAILABLE_KIB=14155776 \
ROCQ_STACK_KIB=262144 \
ROCQ_MEMORY_SWAP_MAX_KIB=0 \
  "$repo/work/run-memory-guarded.sh" \
  timeout --signal=TERM --kill-after=5s 900 \
  dune build -j1 topbin/rocqworker.exe
```

Only after that command has exited, run the continuation. This
admits exactly one Rocq worker, caps the complete cgroup at 4 GiB, disables
swap, and stops preventively at 3.75 GiB RSS or if `MemAvailable` reaches
13.5 GiB:

```sh
repo=/home/theo/Documents/github/rocq-lean-typechecker
cd "$repo"
checkpoint_dir="$repo/work/cslib-full-fresh"
checkpoint=CslibFull
log_stamp=$(date -u +%Y%m%dT%H%M%S%NZ)
env -u ROCQ_DIAGNOSTIC_NO_DIRECT_ARGUMENTS \
    -u ROCQ_DIAGNOSTIC_NO_DEPENDENCY_FIRST \
    -u ROCQ_DIAGNOSTIC_PROJECTION_FIRST \
    -u ROCQ_DIAGNOSTIC_CONVERSION_CALL \
    -u ROCQ_DIAGNOSTIC_MEMOIZE_CONVERSION_CALL \
    -u ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL \
    -u ROCQ_DIAGNOSTIC_CONVERSION_TRACE_FROM \
    -u ROCQ_DIAGNOSTIC_CONVERSION_TRACE_PAIRS \
    -u ROCQ_DIAGNOSTIC_CONVERSION_MEMO_LIMIT \
    -u ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES \
    -u ROCQ_DIAGNOSTIC_DEPENDENCY_STATS \
    -u LEAN_IMPORT_DECLARE_TRACE_LINE \
    -u LEAN_IMPORT_DUMP_FAILED_DEF \
LEAN_IMPORT_CHECKPOINT_STATS=1 \
ROCQ_DIAGNOSTIC_SERIALIZATION=1 \
ROCQ_MEMORY_POLL_SECONDS=0.25 \
OCAMLRUNPARAM=s=4M,o=5,i=5,a=2,v=21 \
ROCQ_MAX_RSS_KIB=3932160 \
ROCQ_MEMORY_MAX_KIB=4194304 \
ROCQ_MEMORY_HIGH_KIB=4194304 \
ROCQ_MIN_AVAILABLE_KIB=14155776 \
ROCQ_STACK_KIB=262144 \
ROCQ_MEMORY_SWAP_MAX_KIB=0 \
ROCQ_CHECKPOINT_LOG_FILE="$checkpoint_dir/$checkpoint.$log_stamp.run.log" \
  "$repo/work/run-checkpoint-atomic.sh" \
  "$checkpoint_dir/$checkpoint.v" -- \
  timeout --signal=TERM --kill-after=5s 28800 \
  "$repo/_worktrees/rocq/compact-peano-view/_build/install/default/bin/rocq" \
  c -q -bytecode-compiler no \
  -R "$repo/_worktrees/rocq/stdlib-physical-hconstr/theories" Stdlib \
  -I "$repo/_worktrees/rocq-lean-import/compact-peano-importer-current/src" \
  -Q "$repo/_worktrees/rocq-lean-import/compact-peano-importer-current/src" LeanImport \
  -Q "$checkpoint_dir" '' \
  > "$checkpoint_dir/$checkpoint.$log_stamp.guard.log" 2>&1
```

The runner refuses admission unless `MemAvailable` covers both the 13.5 GiB
reserve and the full 4 GiB budget.  It also refuses a second concurrent
run or any Rocq worker outside its managed scope.  A failed command cannot
replace the canonical `.vo`.

Keep `MemoryHigh` equal to `MemoryMax`: a lower high watermark previously
caused prolonged kernel reclaim throttling. The hard cap and swap prohibition
remain active. Retain supervisor output as well as the compiler log when
running unattended (for example, redirect it to a separate `.guard.log`).

To reproduce the isolated stack-limit regression, use the same command with
`checkpoint_dir="$repo/work/cslib-v2"`, a 2,700-second outer timeout, and:

```text
checkpoint=CslibV2Blocker3847801        ROCQ_STACK_KIB=262144  # passes
checkpoint=CslibV2Blocker3847801Stack8  ROCQ_STACK_KIB=8192    # fails
```

The negative control must fail with `Stack overflow`; it is not part of the
successful checkpoint chain. Run these controls sequentially, never alongside
a continuation.
