# Int32 division import resource regression

## Current result

The September 7 full-input retry also passed `Int32.ofInt_tdiv` at line
7,895,801 by 11:52 Paris time, followed by `Int32.ofInt_eq_ofIntLE_div` and
progress beyond 7.95M lines. Scoped RSS was about 1.48 GiB, under the unchanged
3.75 GiB preventive limit. The [full-pass journal](../cslib-full-fresh/README.md)
records the service, logs and memory counters. This crosses the original
failure in full context; the complete-library pass later stopped at line
11,005,951 with a separate nullary-unit recursor conversion error, without
producing a final artifact. See [the new regression report](../finloop-repro/README.md).
It remains an experimental-kernel result.

The original final proof now checks with the substitution-inspection candidate:
5.411 CPU seconds through serialization, 201,692 KiB cgroup peak, exit 0 and
atomic promotion (`Int32TdivFreshResume.candidate.*`). The saved `.vo` SHA-256 is
`0bdec2124a5f6ba00c6ca84f47e3c553cca826cb5433997b266f01922622199c`.

An A/B control reinstated only the previous identity-substitution restrictions
in the compact-eligibility probe, keeping the same new CClosure interface,
plugin, foundation, dependency prefix, source proof, GC and limits. This worker
(`3c6d14eef207bec9521ab1c7a0d6e5cda9bcab4e9ccb07751d44dd21be8b25b2`)
again grew until the preventive RSS guard stopped it at 1,573,480 KiB, exit 125
(`Int32TdivFreshResume.identity-control.*`). The candidate's saved file was
unchanged. The identity-only restrictions were then removed again. This is a
controlled test of the changed probe, not a rebuild of the complete old kernel.

The coherent foundation and fresh dependency prefix also passed. Foundation
`Lean.vo` SHA-256:
`de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b`;
`Int32TdivFreshPrefix.vo` SHA-256:
`b2ae4b9192edfdaa8f1030d3dfe8d988434129f7bd6379c00b696a0f2f15287c`.
The latter took 94.996 CPU seconds and peaked at 217,348 KiB. Its negative
`Fail Check` confirms it contains dependencies but not the target theorem.
The explicit-compiler Stdlib build and metadata inspection both passed;
its Prelude dependency is the expected `585712035b22d8e85c9ff8a1ed829c20`.

For fresh tests, use the original importer `src` with `-I` (plugin), the new
Stdlib worktree with `-R .../theories Stdlib`, and the separate foundation with
`-Q .../foundation LeanImport`. Place the foundation mapping AFTER the parent
`-Q .../int32-tdiv-repro ""`, otherwise the recursive parent mapping hides it.
Never bypass `.vo` digest checks. The historical attempts below used older or
incoherent foundations and are not evidence against this successful replay.

After restoring the candidate, the same proof passed again (5.525 CPU seconds,
201,316 KiB peak), producing the identical `.vo` hash. A fresh-process reload
and `Print Assumptions` passed (198,768 KiB peak). The latter reports the
existing logical infrastructure: definitional UIP, propositional extensionality,
choice, quotient soundness and primitive integers; it is not an axiom-free or
upstream-kernel result.

Additional controls passed under the same 1.5 GiB guard:

- `closure_inspection.ml`: direct/absent entries, shifts, lifted binders, open
  entries, physical sharing and no reduction of suspended closures. It tests
  the public read-only view, not every internal higher-order representation.
- `FinalBoundedProbesSmoke.v` and `FinalBoundedProbesArithmetic.v`: unchanged
  generic fixtures, each with two successful equalities and two `Fail` checks
  of incorrect equalities. Peaks: 63,176 and 63,944 KiB.
- Indexed-checkpoint unit tests: source nodes, DAG aliases, fragments,
  metadata, branches and invalid data; peak 233,324 KiB.

Logs: `*.verified.{run,guard}.log`, `closure-inspection-test.retry.log` and
`indexed-checkpoint-current.log`. The initial helper test did not compile due
to this Rocq version's `Option` module; using a direct pattern match fixed the
test harness, without changing the candidate. Worker hash after restoration
is again `93b97317…`; no foundation or plugin rebuild occurred during the A/B
comparison. Full cslib completion and upstream compatibility remain unproven.

## Earlier investigation

The fresh complete cslib pass stopped at `Int32.ofInt_tdiv` (line 7,895,801):
the preventive RSS guard stopped the sole worker at 3,934,208 KiB, exit 125.
This occurred during checking, before any full checkpoint was saved.

`export.sh` exports the original Lean 4.27.0-rc1 theorem from
`Init.Data.SInt.Lemmas`, together with its dependencies. It does not replace or
rewrite the proof. The theorem states that, for signed-32-bit-range integers,
conversion to `Int32` commutes with truncating division. The converter is the
same arena version that retains Lean reducibility hints in the full input.

The resulting `Int32Tdiv.lean-export` has 233,043 lines (5,412,124 bytes), SHA-256
`3a9c7e78930a1eca1c82b2c5ea824fdd8888bd5e0a1b01b58fe434a383f89f3b`.
This is a dependency-only reproducer, not a minimal standalone Lean example.
Guarded generation passed, with a 529,280 KiB cgroup peak.

`Int32Tdiv.v` reproduces sustained heap growth at the final declaration,
line 233,043, with the unchanged experimental worker `239ec13e…` and plugin
`c50b61ef…`. The 1.5 GiB preventive guard stopped it at 1,574,868 KiB (exit 125).
No `.vo` was produced and no typing exception was reported. Logs:
`Int32Tdiv.baseline.run.log` and `Int32Tdiv.baseline.guard.log`.

`Int32TdivPrefix.v` saved the dependencies successfully (96.637 CPU seconds
through serialization; 216,956 KiB cgroup peak), including its negative check
that the target has not been declared. Prefix `.vo` SHA-256:
`c5b7f5ee7e59d65a26aaaa277d0ea6470745693a0ed1b1fa13d924b9cc10020e`.
It contains 2,658 entries and 214,511 expression nodes.
`Int32TdivResume.v` reloads this prefix in a fresh process and checks only the
original final declaration. These diagnostic artifacts must never be inserted
into the canonical cslib checkpoint chain.

## Located conversion

The 90-second resume with `ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES=1` and
`LEAN_IMPORT_DECLARE_TRACE_LINE=233043` stopped at its diagnostic deadline
(exit 124, 1,069,888 KiB cgroup peak). Translation of the source body completed
at CPU 1.230; kernel checking then entered conversion calls 216 through 221.
Call 221 did not return before the deadline. Logs: `Int32TdivResume.entries.*`.

A separate intentional stop using `ROCQ_DIAGNOSTIC_CONVERSION_CALL=221`
identified two applications of the `LE_inst1` projection with the same
`Int_instLEInt` source. Their second argument is the same variable. Their
first arguments differ: `Int32_toInt ...` versus an application of the integer
negation projection. This diagnostic exits 1 intentionally; it is not an
independent typing rejection (`Int32TdivResume.call221.*`).

A 20-second trace using `ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL=221` shows
the left side reaching `BitVec_toInt`, while the right unfolds integer
division and then natural division. The optional bounded compact-evaluation
eligibility test repeatedly declines closures with nonidentity substitutions;
the dependency query also returns unknown for those closures and case stacks.
These are observed fallback reasons, not proof that relaxing a check is safe
or that it alone will fix the allocation. The trace times out as intended
(exit 124, 412,796 KiB cgroup peak; `Int32TdivResume.trace221.*`).

Next: inspect the closure/substitution handling on this exact conversion and
test a generic, bounded correction. Do not raise the memory cap or treat the
negative diagnostic exits as completion of the proof.

All commands must use `../run-memory-guarded.sh` (export) or
`../run-checkpoint-atomic.sh` (Rocq). Run only one at a time; retain the 1.5 GiB
RSS/cgroup cap, zero swap, 256 MiB stack, 13.5 GiB system reserve, and
`OCAMLRUNPARAM=s=4M,o=5,i=5,a=2,v=21`. The full-pass command in the checkpoint
journal supplies the toolchain/load paths; this diagnostic additionally uses
`-Q` for this directory. Do not retry the complete cslib pass unchanged.

At this earlier stage: resource failure reproduced; root cause and generic correction were
not yet established. No importer/kernel implementation was changed for this
reproduction.

## Substitution-inspection candidate: initial build history

A later experimental patch adds `CClosure.inspect_substituted_rel`, a read-only
lookup returning an unlifted substitution entry. The bounded compact-closedness
probe in `conversion.ml` uses it to inspect referenced entries of nonidentity
substitutions, including beneath binders. It does not reify or reduce the
closure, retains the 1,024-visit budget and update-alias checks, and leaves
ordinary conversion checking in place. The separate dependency probe was not
changed. This is a candidate, not a demonstrated fix.

Worker SHA-256: `93b97317727e726c7b27b45c829536fba090085832e508b99fff4d8b3aafe4d0`.
Rebuilt importer plugin: `80f5f5d5ee4d1e6b236931bfdd3757881661c1a2c54fd3dd00d0bea919d91a29`.
The initial worker build passed (444,224 KiB cgroup peak), but adding a public
interface also required rebuilding the runtime plugins. `@install` built
available components but failed for absent optional GUI/dev-tool dependencies;
the explicit `rocq-runtime.install rocq-core.install` targets then passed.
No new system dependency was installed. Importer `make -B` rebuilt the plugin
against the local runtime; ordinary `make` alone had reported it up to date.

This runtime build regenerated Corelib. The old `Lean.vo` requires Prelude
library digest `577c3b0b360090a6711c092dcc74567e`, whereas the rebuilt Prelude has
`585712035b22d8e85c9ff8a1ed829c20`. Candidate proof replays therefore stopped at
loading, before testing the patch. No digest check was disabled. The read-only
`inspect_vo_summary.ml` diagnostic confirmed the mismatch; the other inspected
local 9.3 copies do not match either. The old `Lean.vo`, test prefix and cslib
checkpoints remain unchanged, but they cannot currently be used with this new
Corelib. Their preservation is not a claim of current reload compatibility.

To establish a coherent test environment without overwriting the old Stdlib,
the detached worktree `_worktrees/rocq/stdlib-int32-repro` uses the same clean
Stdlib commit `3e47b26f345f36e375d81ade399eed0e310984b3`. Its required arithmetic
and micromega subset is being built with the current runtime, one job and the
1.5 GiB cap (`stdlib-coherent-build.log`). Next build a separate `Lean.vo`
from unchanged importer foundation source, and a fresh small dependency prefix.
Compare the candidate and the old conversion probe using those same foundation
artifacts before attributing a result to the patch. Do not rerun full cslib yet.

### Foundation build and guard follow-up

The first subset build was interrupted by a guard race, not an OOM or proof
failure: `/proc/PID/stat` disappeared between a readability test and Bash's
`$(<file)` read. A deterministic test confirms that the shortcut can exit the
supervisor despite `|| return 1`. Both guard copies now use a direct,
NUL-delimited `mapfile` read and reject empty records. The test failed before
the change and passes afterward, including multiline process names and zombie
states. All 23 launcher/proc-reader tests pass; memory limits are unchanged.

The resumed build completed, but metadata inspection found that its generated
Makefile had used the PATH compiler: `ROCQBIN` selected the Makefile generator,
whereas the generated recipes use `COQBIN`. That result required the installed
Prelude digest `39dee337…`, not the candidate's `58571203…`, so it was rejected
as a candidate foundation. A single forced pass of `Makefile.coq` with both
compiler variables set explicitly is now rebuilding all six required targets
(`stdlib-coherent-build.explicit-coqbin.log`). `/proc/PID/exe` of its scoped
worker confirms the candidate worktree's `rocqworker.exe` is actually running.

`foundation/Lean.v` is a byte-identical copy of the current importer source
(checked with `cmp`), not a rewritten proof library. Its first compilation
correctly rejected the wrong-producer Stdlib; retry only after the explicit
compiler build succeeds and its dependency digests have been checked.
`Int32TdivFreshPrefix.v` and `Int32TdivFreshResume.v` are prepared for the coherent
foundation. Neither has passed yet; old diagnostic prefixes remain preserved.
