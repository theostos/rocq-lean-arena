# Projective-spectrum timeout: projected constant dictionaries

Target: NDJSON **13,626,505**,
`AlgebraicGeometry.ProjectiveSpectrum.Proj.toOpen_toSpec_val_c_app`.

## Fix (validated)

`projected_record_wrapper` was firing even when a constant record had **no
arguments before its first projection**. It therefore unfolded a shared
method implementation instead of preserving that method head for congruence
of the arguments applied *after* projection. For `CommRingCat.instCategory`,
this expanded composition into large ring-hom and chosen-inverse structures.

The repair requires a nonempty argument application **before** the first
projection before using this shortcut. Shifts and sharing updates do not count
as arguments, and later applications to the selected method do not count as
wrapper inputs. Parameterised wrappers retain their existing behaviour.
No conversion rule, dependency cache, proof-checking flag or canonical timeout
has been weakened or disabled.

Fixed worker SHA256:
`9645f46ccef126cb18fbba9f6cbf54356a98cce830e27d2e3190fcbccd6d701e`.

`projected-constant-target` passes with all normal heuristics enabled:
conversion 290 takes **17.868 CPU seconds**, and the declaration takes
**22.838 CPU seconds** (58.458–81.296), versus the baseline's 1,800-second
canonical timeout. The new `projected_constant_congruence.v` regression
passes in 0.55 seconds; the baseline times out on its first case. It covers
both directions, binders, preserving parameterised-wrapper shortcuts and
rejecting unequal relevant arguments.

The focused process completed with exit 0 in **288.706 seconds** including
loading/saving; peak memory was **5,598,536 KiB**. Its saved `.vo` SHA256 is
`3d02bdb31fe867fd6f3d9cbe872c1b445c943c8d3a5749d7d43d165e5e01d598`.
`projected-constant-baseline-final` repeats the failure using the exact final
regression source (rather than an earlier draft).

`validate.py` passed the original-order/module replay from 13M through
13,650,000, a fresh reload, 23 kernel fixtures and 44 importer fixtures.
The runner suite passed 199 tests with 2 skipped (201 total).
`resume.sh` is pinned to the fixed worker and
`validation-hsrd2ui6/passed.json`; it refuses to resume until every required
record and artifact matches. All 13 original checkpoint seals were verified
again without rewriting their sources.

The full original-order replay completed with exit 0 in **634.760 seconds**;
its `.vo` SHA256 is
`06a09750a65d9642472dafcab58f4145b1c3460d0d4dbe0b88ec7843d3592481`.
The fresh reload/save completed with exit 0 in **247.273 seconds**;
its `.vo` SHA256 is
`685a3d1f9228c4b72c2a7d423a256ec00d16de743fa6dd4c5ed21217937483b2`.

After validation and a successful `resume.sh --check`, the full run was
launched under `rocq-mathlib-ndjson-projected-constant.service` on 2026-09-11.
Supervisor log:
`work/mathlib-ndjson/projected-constant-resume.supervisor.log`.
It resumes from the canonical 13M checkpoint, not the isolated partial-14M
validation artifact. The 1,800-second timeout and 16 GiB/no-swap guard remain.

## Original failure

The canonical run from the 13M checkpoint timed out at the unchanged
1,800-second per-declaration limit on 2026-09-11, 10:39:47 UTC. Its last
reported RSS was 5,351,824 KiB. It was CPU-active, not stopped by the memory
guard. The three SIGUSR1 events are monitor-requested stack samples; the
SIGALRM sample is the actual timeout. GDB's missing source-path warnings are
not importer errors.

Canonical attempt:
`work/mathlib-ndjson/attempts/20260911T095605062466Z/MathlibTo14000000.run.log`.
The canonical 13M checkpoint remained intact; the full run was paused while
the repair was investigated and validated.

The sampled stacks show nested argument conversion, with different samples
in unit-type inspection, compact-operation dependency queries, unfolding and
successful-conversion-cache lookup. None of these samples alone establishes
which helper is responsible for the overall cost. The initial wide-congruence
hypothesis was investigated but did not fix this declaration.

The original Lean theorem is in
`_deps/lean-kernel-arena/_build/tests/work/mathlib/src/Mathlib/AlgebraicGeometry/ProjectiveSpectrum/Scheme.lean:702`.
Its proof uses `Eq.trans (by rfl)` and a general adjunction lemma.

`conversion.baseline.ml` and `rocqworker.baseline.exe` preserve the unchanged
type-alias-repair kernel, worker SHA256
`4c35ea0349dc0cb1c22d7d80acc6a456b9de9f31851af26be7868404f72415b3`.

`run.py` reuses the prior isolated, hash-checking, single-worker replay harness.
The staged `prefix/MathlibTo14000000.v` rechecked 13,000,001–13,626,504 in original
order and under the original module name to create a focused-replay prefix.
The top-level `MathlibTo14000000.v` now extends validation through 13,650,000. `Target.v`
uses the normal 1,800-second limit. `Trace.v` lowers it to 120 seconds only for
an isolated diagnostic; it does not change canonical limits.

All experiments preserve proof checking, checkpoint seals and the memory guard.

## Checked prefix and focused experiments

`prefix/result.json` records a successful original-order replay through
13,626,504 with the validated baseline worker. It took 575.75 seconds including
saving; peak memory was 6,210,432 KiB. The focused theorem reuses that checked
prefix. Translating its type/body and universes takes less than 0.04 seconds;
kernel conversion call 290 consumes the timeout.

The following isolated trials all retain full kernel checking. Their 120-second
declaration limit is diagnostic only; no canonical settings were changed.

| Stage | Change from baseline | Outcome |
| --- | --- | --- |
| baseline-entries | entry timing only | timeout in call 290 |
| baseline-trace | bounded scalar trace | timeout; over 16M steps, 147 memo clears |
| work-budget-target | 4,096-step speculative congruence budget | timeout |
| projection-first-target | existing projection-first strategy | timeout; 11,687,408 KiB peak |
| carrier-builder-target | record-builder unfolding trial plus work budget | timeout |
| large-memo-target | memo capacity 1,048,576 instead of 32,768 | timeout before first eviction |
| no-dependency-target | omit dependency-first pass | timeout |
| no-direct-target | omit constructor-first argument ordering | timeout |
| path-target | baseline semantics, active comparison-path trace | timeout |
| named-projection-target | unfold named primitive-field selectors before congruence | timeout; initial branch drops from about 1.2M to 23K steps |
| fast-syntax-target | bounded structural comparison through substitutions | timeout |

The work-budget trial fixes a separate small width-explosion example
(`wide-baseline` fails, `wide-work-budget` and `work-budget-regression` pass),
but does not establish a repair for this Mathlib theorem. Its proposed test
is therefore kept as `CongruenceWorkBudget.v` in this investigation, not in
the kernel success suite. Both unsuccessful semantic trials have been removed
from the active kernel source and preserved as `conversion.work-budget.ml`
and `conversion.carrier-builder.ml`, with matching worker snapshots.

`NamedProjection.v` also reproduces a smaller selector problem: baseline
times out after five seconds; the selector trial checks it in 0.57 seconds.
This is not sufficient to establish a repair for the original declaration.
The selector and structural-equality trials are preserved in matching source
and worker snapshots and have been removed from the active source.

The comparison-path trace identifies two stages: first, congruence of
`RingHom_comp` descends into the entire `Algebra` supplied to `algebraMap0`;
then comparing chosen inverses descends through `Classical_choice` into a
large subtype predicate, natural transformations, functors and structure
sheaves. These are actual parent comparisons, not just sampled leaf helpers.

The constructor-relevance-first trial and the combined relevance/projection
trial also hit the diagnostic timeout. The projected-alias classifier extension
fixes `ProjectedAlias.v` (baseline times out; candidate 0.54 seconds), but the
original theorem still times out. All these trials have been removed from the
active source and preserved as source/worker snapshots.

## Successful control: ordinary unfolding oracle

`plain-oracle-target` uses the **unchanged validated baseline worker**, but
`PlainTrace.v` unsets `Kernel Conversion Dep Heuristic` immediately before the
isolated declaration. Proof checking remains enabled. This succeeds:

- declaration: CPU 55.448–56.595, **1.147 seconds**;
- conversion 290: CPU 55.674–56.437, **0.763 seconds**;
- complete process including prefix load and saving: **247.897 seconds**, exit 0;
- saved `.vo` SHA256:
  `4ee6c5dd15879690e15e40e71de260ae1f110a17877fa27f5f2891ed1ae01b5f`.

This establishes that the enabled unfolding heuristic causes the pathological
cost, rather than proving a bottleneck in the dependency cache itself. The
earlier `--no-dependency-first` control does **not** disable the entire heuristic:
it leaves constructor-argument unfolding preference and other guards enabled.

Disabling only constructor-argument unfolding preference still times out, as
does disabling both that preference and dependency-first ordering.
Disabling only the projected-record shortcut (`no-projected-wrapper-target`)
instead checks conversion 290 in **3.689 seconds**, with dependency tracking
and successful-conversion caching still enabled. This identifies the culprit.
The final repair narrows that shortcut rather than disabling it globally.

`Probe.v` deliberately errors *after* a kernel-checked import, so it cannot
produce a successful validation result or checkpoint. Its stage's exit code 1
is not itself evidence of a timeout: inspect the declaration's completion and
the final diagnostic marker. It is not used by the final validation gate.
