# Fresh complete cslib check

Status: **the September 7 retry stopped at line 11,005,951 with a typechecking
error; no completed full-library result**. The original failing proof now passes
with an importer-only fix; see the [checkpointed manual retry](CHECKPOINTED-RUN.md).
No full retry has been launched. This experiment uses
the modified experimental kernel, not upstream Rocq. The last saved canonical
checkpoint remains [9.5M](../cslib-v2/README.md#verified-frontier).

## September 7 restart after interruption

The September 6 corrected run is no longer live. Its final progress entry was
`Lean_Meta_RefinedDiscrTree_ModuleDiscrTreeRef.(field).ref30`, line 5,790,297;
its final guard sample was at 19:29:47 (1,329,460 KiB aggregate RSS). There is
no recorded typing error, guard termination or final `CslibFull.vo`. The host
subsequently rebooted. The logs do not establish the cause of the interruption;
this is neither a completed pass nor a demonstrated OOM. No intermediate
artifact exists from which to resume this fresh run.

The unchanged proof input, kernel, plugin and foundation were rechecked before
restarting from the beginning at 09:44 on September 7 (Paris time). Current unit:
`rocq-cslib-substitution-aware-20260907.service`, invocation
`384a9210ab644a94baf08f6d0b69ee12`. Logs:
`CslibFull.substitution-aware-20260907.{service,guard,run}.log`.

At 10:08 this retry had passed `Lean.Meta.DiscrTree.Trie.casesOn` (1,210,790)
and `Lean.Parser.decimalNumberFn.parseScientific` (2,057,475), with subsequent
progress beyond 2.064M lines. Aggregate RSS was 590,412 KiB (about 577 MiB).
These are fresh-run non-regressions, not a saved full-library result. At that
point, the `Int32.ofInt_tdiv` target at 7,895,801 had not yet been reached.

At 10:38 the same retry also passed `Int16.toInt_lt` (3,847,801), followed by
`Fin.eta`, `Fin.mk_val` and later declarations beyond 3.85M lines. Aggregate
RSS was 1,126,824 KiB (about 1.07 GiB). No kernel, plugin, proof or safety-limit
change was made during this observation.

At 11:07 it passed `Int32.toInt_lt` (5,402,976), followed by
`Int32.toNatClampNeg_lt` and subsequent progress beyond 5.44M lines. Aggregate
RSS was 1,178,724 KiB (about 1.12 GiB), with the same worker, plugin and limits.

At 11:10 it also passed `Int32.toBitVec_not` (5,534,591) and
`ENNReal.one_lt_two` (5,536,463), with later progress beyond 5.58M lines.
Aggregate RSS was 1,193,524 KiB (about 1.14 GiB). These are non-regressions in
the same fresh run, not additional fixes or a complete-library result.

At 11:21 the retry progressed beyond 5.869M lines, surpassing the interrupted
September 6 run's last entry at 5,790,297. Aggregate RSS was 1,330,828 KiB
(about 1.27 GiB). At that point, the full-context `Int32.ofInt_tdiv` check at
7,895,801 and complete-input checks were still ahead.

By 11:46 this retry had passed `Lean.Widget.MsgEmbed._sizeOf_2_eq` (7,216,963)
and the merge-sort auxiliary proof at 7,387,715, followed by
`Cslib.Algorithms.Lean.TimeM.mergeSort_same_length` (7,387,820) and progress
beyond 7.50M lines. Aggregate RSS was 1,517,108 KiB (about 1.45 GiB).
The worker, plugin, source proofs and resource limits remain unchanged.

At 11:52 the same full-input run passed **`Int32.ofInt_tdiv` (7,895,801)**,
followed by `Int32.ofInt_eq_ofIntLE_div` (7,895,893) and later declarations
beyond 7.95M lines. Aggregate scoped RSS was 1,549,832 KiB (about 1.48 GiB).
At the immediate follow-up inspection, the cgroup's peak for the entire run
so far was 1,576,226,816 bytes (about 1.47 GiB); its OOM counters and swap usage
were zero. These are whole-run memory observations, not per-theorem timing or
memory measurements. RSS sums and cgroup accounting are different metrics.

This confirms that the original failure point is crossed in full context,
not just in the dependency-only reproducer. It does not establish completion
of the 22.8M-line import, a saved full artifact, fresh reload or stock-Rocq
compatibility. No proof rewrite, toolchain change or limit increase was made
during this retry; the controlled A/B evidence is in the reproducer journal.

At 12:29 the same fresh run passed `Std.DHashMap.Const.size_ofList` (9,486,735)
and progressed beyond 9.50M lines, crossing the old saved-checkpoint frontier.
Aggregate scoped RSS was 1,986,604 KiB (about 1.89 GiB), without loading the
old checkpoint chain. This is a checking-progress observation, not a new saved
checkpoint or a prediction that the remaining input and serialization will
fit within the unchanged memory cap.

At 12:39, progress reached line 10,036,096 (`Quotient.decidableEq.match_1`),
still at 1,986,604 KiB aggregate RSS. The scope's OOM and memory-limit event
counters were zero. Checking has therefore continued beyond the old 10M
range; this does not exercise the final serialization that failed in the
earlier checkpoint-chain run. The same invocation was still live at that time.

At 12:59 it terminated with an `Illegal application` of `Eq_trans` at line
11,005,951 (`Cslib.Automata.NA.FinAcc.instTotalSumUnitFinLoopOfNonemptyElemStart`).
The preceding `Std.HashMap.ofList_eq_insertMany_empty` check had completed.
Compiler/guard status was 1, peak cgroup memory 2,003,408 KiB; this was not an
OOM or a timeout. No full artifact was saved. The importer-only nullary-unit
scheme fix and smaller reproduction results are in
[the regression report](../finloop-repro/README.md).

```sh
systemctl --user status rocq-cslib-substitution-aware-20260907.service
tail -n 20 work/cslib-full-fresh/CslibFull.substitution-aware-20260907.guard.log
```

To stop this run (tested with the complete launcher):

```sh
systemctl --user stop rocq-cslib-substitution-aware-20260907.service
```

For a later intentional retry, after confirming the previous scope is inactive:

```sh
bash work/cslib-full-fresh/start-substitution-aware-service.sh NEW_UNIQUE_TAG
```

The user service is independent of the terminal; it does not automatically
restart after a reboot. The guard's optional `ROCQ_MEMORY_OWNER_SERVICE`
verifies the enclosing service cgroup, then binds the separate scope to that
service with `BindsTo`/`After`. Without that binding, a real cancellation test
showed that stopping the checkpoint service left its scope running. That test
used only `sleep`, was explicitly stopped, and preserved the canonical artifact.
The bound cancellation test stopped both units before the sleep expired, with
guard status 143 and no artifact promotion. Neither memory limits nor Rocq
checking settings were relaxed.

The original `Int32.ofInt_tdiv` proof also passed in the bound service: guard
exit 0, cgroup peak 201,592 KiB, and the same `.vo` hash `0bdec212…` as before.
Logs are `../int32-tdiv-repro/Int32TdivFreshResume.bound-service-20260907.*.log`;
cancellation logs use `bound-cancel-service-20260907`. All 38 existing lightweight
launcher/proc-reader/evidence-audit tests passed; these are not a full-library
proof or a general test of all systemd failure modes.
The additional `test_guard_service_owner` regression checks 16 combinations
across both guard copies (matching owner, absent owner, invalid/mismatched
owner and missing cgroup-v2 entry), without starting any service or workload.

The evidence gate for this retry is:

```sh
python3 scripts/audit_rocq_full_pass.py work/cslib-full-fresh/substitution-aware-20260907.audit.json
```

It must remain negative until completion; use systemd state, not log timestamps
or the audit result, to establish process liveness.

## Current replay: substitution-aware compact eligibility

The original `Int32.ofInt_tdiv` proof now passes in the dependency-only
reproducer: about 5.5 CPU seconds and 197 MiB peak, versus an identity-only
A/B control stopped at the 1.5 GiB limit. See the
[reproduction and regression results](../int32-tdiv-repro/README.md).
The generic correction inspects referenced closure substitutions without
expanding them; it changes the choice of reduction strategy, not the proof.

The current replay uses worker `93b97317…`, plugin `80f5f5d5…`, a coherent rebuilt
Stdlib subset and a separate `Lean.vo` (`de89adf1…`) compiled from unchanged
foundation source. Do not use the old checkpoint chain with this Corelib.
The original old artifacts and logs remain preserved.

The original foreground command, using a unique unused tag, is:

```sh
ROCQ_RUN_TAG=NEW_UNIQUE_TAG bash work/cslib-full-fresh/run-substitution-aware.sh
```

The launcher checks the fixed export/worker/plugin/foundation hashes, retains
the singleton memory guard and refuses to overwrite existing logs. For a later
intentional retry, use a new `ROCQ_RUN_TAG`. Never start a second run while one
is live. The interrupted September 6 logs are
`CslibFull.substitution-aware.{run,guard}.log`.
All safety settings below are unchanged: 4 GiB hard cap, 3.75 GiB preventive
RSS stop, 13.5 GiB system reserve, no swap and one heavy process.
The earlier failed run below used a different foundation and worker.

The corrected run started September 6 at 17:57 Paris time. At 17:58 it had
passed 107,000 export lines with about 199 MiB aggregate RSS. This is progress
only, not a checked complete library or a saved checkpoint.

At 18:21 the same corrected run had passed
`Lean.Parser.decimalNumberFn.parseScientific` (2,057,475) and progressed beyond
2.09M lines, with 590,296 KiB aggregate RSS (about 576 MiB). This is a fresh
non-regression at an earlier blocker, not completion of the full input.

At 18:49 it also passed `Int16.toInt_lt` (3,847,801), with subsequent progress
beyond 3.86M lines. Aggregate RSS was 1,126,708 KiB (about 1.07 GiB), still under
the unchanged limits. No runtime, importer or source-proof change was made
during this observation.

At 19:17 the same run passed `Int32.toInt_lt` (5,402,976), followed by
`Int32.toNatClampNeg_lt` and later declarations beyond 5.43M. Aggregate RSS was
1,178,608 KiB (about 1.12 GiB). This confirms another fresh-run non-regression
with the substitution-aware candidate; the target `Int32.ofInt_tdiv` at
7,895,801 has not yet been reached in the full run.

At 19:20 it passed `Int32.toBitVec_not` (5,534,591), followed by the BitVec xor
lemmas and subsequent progress beyond 5.58M. Aggregate RSS was 1,193,408 KiB
(about 1.14 GiB); the worker, plugin, proof input and limits are unchanged.

## Why restart?

The 9.5M-to-10M continuation checked all its declarations, but the memory guard
stopped checkpoint encoding at the 3.75 GiB preventive RSS limit. It produced
no 10M checkpoint. The accumulated chain contains 27 full importer snapshots:
1,622,655,374 serialized bytes (1.51 GiB), in addition to Rocq's declarations.
These payloads remain loaded with the ancestor libraries.

`CslibFull.v` requires only `LeanImport.Lean` and reads the entire fixed export
to EOF. It does not load any earlier cslib checkpoint, delete any file, change
the importer/kernel, or rewrite a library proof. It retains strict failure
mode, disables missing-quotient skipping, parsing-only mode and lazy declaration
checking. Universe instantiation otherwise follows the importer's default
policy; possible instances are not a count of instances actually checked.

Avoiding the old snapshots should reduce retained memory, but the live source
graph and Rocq environment still grow. Full-library completion under the cap
is unproven. A fresh pass also exercises the early export with the current
importer and strict settings instead of reusing older checked artifacts.

## September 6 baseline artifacts (SHA-256)

- Export: `ce6fb77ab3905e0dbbc9668dad42f3cbfee474c131b472140cc4da94f8b323ae`
- Importer plugin: `c50b61ef63d06f102ad33b7a4601e11d1550667fe93e14ff229c21ae3daad175`
- Experimental worker: `239ec13ec07713f0b8781711fb72ac615607140d725eb38a6d09cca6a84ab5d6`
- `Lean.vo`: `f50cec8bb0b9ebbc5e461e6a8e8339cfd09cc80f43a2d2a39f3379c72718aba5`

The fixed export has 22,828,731 physical lines. Its last entry is
`#HINT_OPAQUE 1532051 21039030 21039123`, named `List.pairwise_le_finRange`.
The final dense IDs imply 21,039,124 expression nodes and 1,532,052 names.
Reaching a smaller frontier does not establish completion. Lean version:
4.27.0-rc1. Existing ancestors and input
hashes were checked before launch; no worker or plugin was rebuilt for this run.

## Existing elimination-compatibility setting

There is a second qualification besides the experimental worker. The importer
already uses `with_unsafe_univs` to set `check_eliminations = false` temporarily
when its Lean/Rocq squashing classification differs for a single inductive
declaration; it restores the flags on both success and exception. The current
switch predates this run (importer commit `50802fbc22c96706189a070ab7e9da6f34a90409`,
February 5, 2026); that commit replaced the broader `check_universes = false`.
Neither switch was added or changed during this fresh pass.

In this worker, `kernel/indTyping.ml:compute_elim_squash` skips the corresponding
elimination/universe-bound calculation when this flag is disabled. This is not
the same as disabling all universe, positivity, guard or definition-body checks.
It remains an inherited translation assumption to audit, not evidence that
the imported inductives satisfy default Rocq elimination checks. An eventual
standard-checking claim must inspect per-inductive `mind_typing_flags` and the
affected cases; seeing restored global flags or no error in the log is not
enough. This source audit did not enumerate the affected declarations in the
live process or establish that the restricted use is unsound.

## Arithmetic registration source audit

A read-only inspection found that binary arithmetic registration is not based
on names alone. `safe_typing.ml:check_register_peano_nat_operation` checks a
transparent operation's type and its zero/successor computation equations under
binders. `peano_baseline_env` clears the Peano arithmetic/comparison tables and
the conversion oracle for these comparisons, avoiding validation using the
same Peano shortcut being registered. It is still the experimental kernel,
not a separate stock-kernel check. `checker/mod_checking.ml:apply_peano_actions`
also calls the registration checks before replaying saved actions.

The source contains negative registration fixtures for incorrect addition,
subtraction and exponentiation (`test-suite/success/compact_peano.v`). They were
not rerun during this full pass, and this inspection neither executes the saved
action checker nor proves correctness of all recognizers or accelerated
reducers. No arithmetic implementation or registration changed during the audit.

## Run and safety

Use the [guarded full-pass command](../cslib-v2/README.md#safe-fresh-full-pass),
never an unguarded Rocq invocation. Do not start a second run while one is live.
The source has no intermediate save command; final output is staged and promoted
only after the compiler exits zero with a nonempty `.vo`.

- One heavy job; cgroup cap 4 GiB; no swap.
- Preventive aggregate RSS limit 3.75 GiB; system available-memory reserve 13.5 GiB.
- Stack cap 256 MiB; guard poll 0.25 seconds.
- GC: `s=4M,o=5,i=5,a=2,v=21`.
- Declaration timeout 600 seconds; whole-run timeout 28,800 seconds (8 hours).

The first run started September 6 at 14:14 Paris time. Logs:
`CslibFull.small-growth-gc5-4g.run.log` and
`CslibFull.small-growth-gc5-4g.guard.log`. Its initial checks started normally.

At 15:13 Paris time the same process had progressed beyond 4M lines, with about
1.08 GiB aggregate RSS. The log confirms that the earlier blockers at
`Lean.Parser.decimalNumberFn.parseScientific` (2,057,475) and `Int16.toInt_lt`
(3,847,801) were passed in this fresh run. This is observed checking progress,
not a saved full-library result; no new compiler, plugin or proof change was
introduced during this observation.

By 15:50 the run had progressed past both `Int32.toInt_lt` (5,402,976) and
`Int32.toBitVec_not` (5,534,591), the two arithmetic regressions described in
the checkpoint journal. It also passed `ENNReal.one_lt_two` (5,536,463), where
an earlier GC experiment had been interrupted rather than shown to fail.
These are fresh-run non-regressions with the unchanged worker/plugin, not new
fixes or new saved checkpoints. Aggregate RSS was about 1.22 GiB near 5.62M.

Even a successful complete result here would establish a pass with the modified
experimental kernel, not completion of the upstream-standard-kernel objective.

## Completion checks

The September 6 run stopped at 16:34 Paris time with exit 125 while checking
`Int32.ofInt_tdiv`, export line 7,895,801. Aggregate scoped RSS reached
3,934,208 KiB, exceeding the unchanged 3,932,160 KiB preventive limit. No
`CslibFull.vo` was produced. The last progress entry was this declaration;
the subsequent output reports heap growth and GC, not a typing exception.
The scope is now inactive. This is a resource failure during checking, not
the earlier ancestor-checkpoint saving failure. Do not retry the full pass
unchanged: next isolate the original Lean declaration and its dependencies.
The existing canonical 9.5M checkpoint remains preserved; it does not prove
that this fresh pass with the current worker succeeds through that frontier.

The fresh run passed `Lean.Widget.MsgEmbed._sizeOf_2_eq` (7,216,963) and
the merge-sort proof at 7,387,715 before this stop. No kernel/plugin change,
library proof rewrite, or memory-limit increase occurred during the run.

Do not infer success from a running process, a progress line, or `Done!` alone.
Require compiler/guard exit zero and atomic promotion of a nonempty `CslibFull.vo`;
verify the final entry at line 22,828,731, the complete-input node/name counts,
and no reported errors, skips or timeouts. Rehash the source/export/toolchain
artifacts after the run and inspect the saved checkpoint envelope and digest.
Fresh-process reload remains a separate test; this run must be terminal before
starting it. Upstream-kernel compatibility and clean integration remain separate
uncompleted requirements even if these experimental-run checks pass.

The read-only evidence gate for the corrected run is:

```sh
python3 scripts/audit_rocq_full_pass.py work/cslib-full-fresh/substitution-aware.audit.json
```

Run this from the repository root. It requires the exact final entry and
name/node counts, one `Done!` summary, no recorded errors/skips, one successful
guard termination, promotion of the expected nonempty `.vo`, and matching
manifest hashes for the driver, export, worker, plugin and foundation. It
reports the resulting artifact hash. While those log gates are incomplete it
exits 1 without hashing the large input or artifact. It does not determine
whether a process is alive: use the original process handle for that.

This gate inspects trusted run evidence, not the proof contents. It neither
replaces fresh-process reload and kernel/assumption audits nor establishes
stock-Rocq compatibility. Its 15 small synthetic tests pass; they start no
Rocq process or cgroup. On the live run near 1.2M lines, the CLI correctly
reports `run_evidence_complete: false` and exits 1.
