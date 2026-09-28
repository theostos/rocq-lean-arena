# Mathlib on homepc

**Reproduction: [QUICKSTART.md](QUICKSTART.md).** The strict run completed on
24 September; the cleaned branch stacks also passed on 26 September
([source pins and result](SUBMISSION.md)). The survey reports below are historical.

## Thirty admitted theorem diagnostics

**30/30 theorems, 36/36 recorded instances measured.** Both diagnostic jobs completed successfully.

- 7 theorems: expensive missing dependency-instance generation/checking.
- 20 theorems: kernel conversion/type-comparison cost.
- 3 theorems: fast after checkpoint reload; original cold cost remains a separate test.
- Controlled strategy change: gluing helper passes in 9.01 s and integrality theorem in 46.14 s; Lie trace still times out.
- Main batch: 21.0 minutes, up to 7 workers, 88.4 GiB aggregate peak. One extra strategy-control worker ran in parallel.

[Full per-theorem report](README.md) · [Measured data](measured-evidence.json) · [Stage table](STAGES.md)

Production and checkpoint admissions are unchanged. All diagnostic workers have exited; their memory is released.

## Exploratory timeout survey

**Contains admitted proofs; this is not a checked Mathlib prefix.**

Phase: discovery complete; baseline replay complete. Saved exploratory records: 100,001,405 / 100,001,405.
All scoped export records reached; final checkpoint saved.
Historical targets across attempts: 36; theorem timeout targets: 33.
Theorem cutoff: 180 seconds. Definitions/inductives: checked retry up to 1800 seconds.
Checkpoints: 20M, 40M, 60M, 80M and EOF. Five regression workers follow discovery.
Generation: `/media/theo/68998cde-9250-435b-ae2b-5122d9c4b9af/home/theo/Documents/rocq-mathlib-homepc-20260919/mathlib-survey-no-proofwidgets-20260921`.
Latest saved checkpoint ledger: 32 targets, 30 admitted theorems. Historical timeouts can pass in a later attempt.
Indexed mutual recursor repair: [mathlib-lists-equiv-20260921](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-lists-equiv-20260921/README.md).
Lists.Equiv.casesOn at 58,576,845 now checks without admission. The qualified importer resumed from the preserved 40M checkpoint. Current phase and position are shown above.
Mayer–Vietoris admission timeout investigation: [mathlib-mayer-vietoris-20260922](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-mayer-vietoris-20260922/README.md).
Mayer–Vietoris candidate: original proof passed in 54.6s including loading and saving.
Mayer–Vietoris candidate: exact statement admission passed in 46.9s including loading and saving.
Matched old/new regression comparison: 17/17 finished; 10 passed; new regressions: 0.
One historically passing case currently times out on both old and new kernels; the 180-second cutoff is unchanged.
Qualified native repair passed its production-overlay original-proof control. Current survey phase and record are shown above.
JSON surrogate parser memory investigation: [mathlib-json-parser-20260922](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-json-parser-20260922/README.md).
JSON candidate checks: JsonCase passed (6.6s), MayerCase passed (38.1s), AbbrevControl passed (1.4s).
JSON repair regression comparison: 17/17 finished; 10 passed; new regressions: 0.
JSON repair passed the production-overlay original-definition and checkpoint-consumer metadata controls. Current survey phase and record are shown above.
JSON continuation: failed; resume-scoped-survey-and-five-workers.
Flasque environment-type scope repair: [mathlib-flasque-20260923](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-flasque-20260923/README.md). Original failure at 83,122,651 in TopCat.Sheaf.IsFlasque.epi_of_shortExact. 80M checkpoint preserved with 28 admissions.
Original proof checked without admission in 33.8s. The standalone scope regression also passes; proof limits are unchanged.
Flasque investigation: flasque-exact: complete; flasque-focused: complete; flasque-reload: complete; flasque-resume: failed.
Identifier encoding repair: [mathlib-name-encoding-20260923](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-name-encoding-20260923/README.md). Stopped at 85,027,975 on an unescaped backtick in a library note. Small importer-only fix; kernel, existing names, and proof policy unchanged.
Original declaration, 392 name/compatibility cases, collision controls, synthetic checkpoint reload, and independent checking passed.
Identifier repair stages: name-cases: complete; name-reload: complete; name-resume: failed.
Group-cohomology admission timeout: [mathlib-group-cohomology-20260922](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-group-cohomology-20260922/README.md). Both proof and admission recovery timed out at 73,457,278. The JSON repair passed in production. The recovery repair retains the 180s proof cutoff and gives fully checked recovery 1800s. The managed stages below show qualification and restart state.
Investigation stages: cohomology-recovery-build: complete; cohomology-recovery-exact: complete; cohomology-recovery-controls: complete; cohomology-recovery-reload: complete; cohomology-recovery-resume: failed.
Recovery investigation: [mathlib-survey-recovery-20260921](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-survey-recovery-20260921/README.md).
Recovery candidate: original failing proof checked in 13.9s including load/save; independent target check 8.6s; admission and 20M reload controls passed.
Recovery regression checks: 17/17 finished; 11 passed, 6 timed out, 0 rejected.
- worker-1: complete; checkpoint 20000000; results 13, passed 11.
- worker-2: complete; checkpoint 40000000; results 6, passed 1.
- worker-3: complete; checkpoint 60000000; results 6, passed 1.
- worker-4: complete; checkpoint 80000000; results 12, passed 3.
- worker-5: complete; checkpoint 100001405; results 2, passed 0.
Regression suite finished; all targets passed: False. A clean import with no admissions is still required.

**Scope change: ProofWidgets UI code is excluded from the remaining import.**
Mathematical statements and original proofs are retained. This is not a pass of the unchanged full export.
Exclusion manifest and dependency audit: [mathlib-proofwidgets-scope-20260921](/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-proofwidgets-scope-20260921/README.md).
Excluded declaration records after 40M: 1111; previously checked UI records inherited in the 40M checkpoint: 40; retained declarations referencing UI: 0.

Updated automatically: 2026-09-24T16:29:38.938633+00:00

**Current-machine saved Mathlib prefix: 100,001,405 / 100,001,405 records. Full import: complete.**

Stages advance locally when their prerequisites pass. Diagnostic slices do not count as full-import checkpoints.

| Stage | State | Current operation | Elapsed |
| --- | --- | --- | --- |
| Rocq + stdlib + importer | complete | importer | 12.4 min |
| Pinned Mathlib export | complete | verify | 12.6 min |
| Large SSD transfer | complete | move-reference-to-ssd | 10.5 min |
| Fresh runtime qualification | complete | receipt | 1.8 min |
| Proof-preserving reproducer | complete | penrose-definition-slice | 16.0 min |
| Penrose baseline replay | failed | baseline-target | 28.2 min |
| Prior Padic regression slice | complete | padic-proof-slice | 6.0 min |
| Small widget conversion diagnostics | failed | synthetic-3000 | 4.4 min |
| Head-beta candidate build and qualification | complete | synthetic-3000 | 6.4 min |
| Exact candidate replays and independent checks | complete | independent-padic | 71.7 min |
| Full Mathlib import (after qualification) | failed | full-mathlib-import | 404.3 min |
| Exact crash diagnosis | failed | capture-exact-crash | 3.9 min |
| New colimit/limit timeout reproducer | complete | proof-preserving-colimit-slice | 6.8 min |
| Binder-context repair build and tests | complete | synthetic-3000 | 14.1 min |
| Colimit repair exact and regression checks | complete | independent-padic | 104.2 min |
| Full Mathlib resume from 20M after qualification | failed | qualify-migrate-resume-from-20m | 151.7 min |
| Fresh 20M reload with repaired runtime | complete | fresh-load-original-20m | 9.8 min |
| Lie trace timeout reproducer | complete | proof-preserving-lie-trace-slice | 3.2 min |
| Lie trace baseline replay | cancelled | baseline-target | 22.0 min |
| Discovery mode and five-worker controls | complete | 12-native-controls-and-6-harness-tests | 0.0 min |
| Exploratory survey and five-worker baseline | failed | discover-and-five-worker-regressions | 32.1 min |
| Opaque-state rollback repair controls | complete | 14-native-controls-passed | 0.0 min |
| Survey restart with opaque-state rollback fix | failed | discover-and-five-worker-regressions | 74.4 min |
| Survey restart after external-worker interruption | cancelled | discover-and-five-worker-regressions | 218.4 min |
| Concurrent guard validation and survey continuation from 20M | failed | discover-and-five-worker-regressions | 198.5 min |
| Admission recovery failure reproducer | complete | proof-preserving-recovery-slice | 9.5 min |
| Admission recovery baseline | complete | reproduce-admission-timeout | 18.5 min |
| Admission recovery candidate controls | complete | native-recovery-controls | 1.5 min |
| Admission recovery candidate replay | complete | candidate-admission-replay | 15.1 min |
| Recovery candidate original 20M reload | complete | candidate-20m-reload | 1.1 min |
| Exact statement admission comparison | failed | exact-statement-admission-comparison | 1.5 min |
| Exact statement admission comparison (corrected name metadata) | complete | exact-statement-admission-comparison | 3.1 min |
| Recovery conventional conversion control | complete | plain-oracle-recovery-control | 6.1 min |
| Recovery projection-first conversion control | complete | projection-first-recovery-control | 0.3 min |
| Projection-first native and negative controls | complete | qualify-projection-first | 0.8 min |
| Projection-first prior 15 targets (five workers) | complete | qualify-projection-first | 7.1 min |
| Projection-first exact proof, independent check and 20M reload | complete | proof-recovery-independent-and-20m-controls | 1.6 min |
| Qualified projection strategy and survey continuation from 20M | failed | discover-and-five-worker-regressions | 350.2 min |
| ProofWidgets dependency audit and exclusion | failed | audit-and-filter-proofwidgets | 0.0 min |
| ProofWidgets completed module inventory and dependency audit | complete | audit-and-filter-proofwidgets | 11.0 min |
| ProofWidgets exclusion native proof and checkpoint controls | complete | native-scope-controls | 0.3 min |
| ProofWidgets-excluded survey from 40M and five-worker regressions | failed | resume-control-scoped-survey | 9.5 min |
| Corrected survey-mode reload and scoped continuation | failed | controls | 0.2 min |
| Survey-mode admission controls, 40M reload and scoped continuation | failed | discover | 172.0 min |
| Lists.Equiv.casesOn failure slice and checked baseline | failed | exact-baseline-replay | 5.6 min |
| Lists.Equiv recursor repair, qualified 40M continuation | failed | resume-scoped-survey-and-five-worker-regressions | 192.7 min |
| Mayer–Vietoris admission timeout proof-preserving slice | complete | proof-preserving-slice | 6.2 min |
| Mayer–Vietoris checked baseline and native timeout samples | complete | checked-prefix-and-exact-recovery-timeout | 23.4 min |
| Mayer–Vietoris three bounded conversion comparisons | complete | three-exact-proof-conversion-controls | 18.7 min |
| Mayer–Vietoris surrounding definition regression slice | complete | proof-preserving-sequence-family | 6.7 min |
| Mayer–Vietoris conversion trace | complete | trace-kernel-conversion-entries | 3.2 min |
| Mayer–Vietoris bounded congruence candidate build | complete | isolated-kernel-and-importer-build | 1.4 min |
| Mayer–Vietoris candidate exact proof and statement admission | complete | exact-statement-forced-admission | 2.4 min |
| Mayer–Vietoris family, independent and focused regressions | failed | qualify | 0.9 min |
| Mayer–Vietoris candidate 16 survey controls | failed | validate_survey | 0.0 min |
| Mayer–Vietoris candidate original 40M reload | complete | check_reload | 2.8 min |
| Mayer–Vietoris candidate five-worker prior target regressions | failed | prerequisite: /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-survey-controls/status.json | 1.5 min |
| Mayer–Vietoris corrected family and focused qualification | failed | qualify2 | 3.6 min |
| Mayer–Vietoris survey controls with original formal libraries | complete | validate_survey2 | 1.1 min |
| Mayer–Vietoris prior targets after corrected controls | failed | five-workers-check-prior-17-cases | 9.2 min |
| Mayer–Vietoris complete focused comparison against producer | complete | focused-old-new-comparison | 0.5 min |
| Mayer–Vietoris complete qualification and independent check | complete | collect-successes-and-independent-check | 0.5 min |
| Mayer–Vietoris matched old/new cyclotomic timing | complete | matched-old-new-proof-replay | 5.4 min |
| Mayer–Vietoris candidate limiting only unbounded fallback | complete | bounded-fallback-native-build | 1.4 min |
| Narrowed candidate original proof and admission | complete | exact-statement-admission | 3.0 min |
| Narrowed candidate family, focused and proof regressions | failed | qualify | 6.8 min |
| Narrowed candidate 16 survey controls | complete | controls | 1.3 min |
| Narrowed candidate original 40M reload | complete | reload | 2.8 min |
| Narrowed candidate 17 historical target regressions | failed | five-workers | 11.2 min |
| Qualified Mayer–Vietoris repair and survey continuation from 40M | failed | prerequisite: /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification3/status.json | 4.8 min |
| Matched old/new 17 proof cases at unchanged 180s limit | complete | matched-seventeen-old-new-cases | 8.6 min |
| Qualified congruence-work repair and survey continuation | failed | resume-scoped-survey-and-five-workers | 305.6 min |
| JSON surrogate memory failure: original proof-preserving slice | complete | proof-preserving-slice | 13.1 min |
| JSON surrogate: checked dependency prefix and native baseline | complete | original-dependency-prefix-and-definition | 20.0 min |
| JSON surrogate: three existing conversion-strategy controls | cancelled | three-existing-conversion-strategies | 1.0 min |
| JSON surrogate: three strategy controls, projection flag actually unset | complete | three-existing-conversion-strategies | 13.8 min |
| JSON surrogate: candidate delayed constructor-demand kernel build | complete | isolated-delta-order-kernel-and-importer | 2.0 min |
| JSON candidate: original failing definition and previous Mayer proof | complete | original-json-definition-and-mayer-proof | 1.9 min |
| json-focused | failed | json-focused | 0.5 min |
| json-reload | complete | json-reload | 2.3 min |
| json-survey-controls | complete | json-survey-controls | 0.9 min |
| json-diagnostic-build | complete | json-diagnostic-build | 0.0 min |
| json-prior-targets | cancelled | json-prior-targets | 4.5 min |
| JSON candidate: Mayer family, independent checks and prior proofs | complete | family-independent-and-previous-proofs | 3.6 min |
| json-build2 | complete | json-build2 | 1.0 min |
| json-candidate2 | failed | json-candidate2 | 4.3 min |
| json-build3 | complete | json-build3 | 1.1 min |
| json-candidate3 | complete | json-candidate3 | 1.9 min |
| json-focused3 | complete | json-focused3 | 0.5 min |
| json-reload3 | complete | json-reload3 | 2.8 min |
| json-survey-controls3 | complete | json-survey-controls3 | 0.9 min |
| json-qualification3 | complete | json-qualification3 | 4.4 min |
| json-diagnostic-build3 | complete | json-diagnostic-build3 | 0.1 min |
| json-prior-targets3 | complete | json-prior-targets3 | 10.8 min |
| JSON repair qualification and survey continuation | failed | resume-scoped-survey-and-five-workers | 190.5 min |
| cohomology-slice | complete | proof-preserving-slice | 13.7 min |
| cohomology-baseline | complete | original-proof-and-admission | 43.7 min |
| cohomology-stacks | complete | sample-traced-target-only | 42.6 min |
| cohomology-comparison | complete | compare-original-proof-strategies | 39.7 min |
| cohomology-diagnostic-build | failed | build-stage-tracing-importer | 0.0 min |
| cohomology-diagnostic-build2 | complete | build-stage-tracing-importer | 0.0 min |
| cohomology-inductive-trace | complete | trace-record-registration | 31.3 min |
| cohomology-monoidal | failed | check-small-monoidal-specialization | 0.1 min |
| cohomology-monoidal2 | complete | check-small-monoidal-specialization | 0.3 min |
| cohomology-no-sharing | complete | original-proof-without-reduction-sharing | 14.4 min |
| cohomology-candidate-build | complete | build-empty-universe-projection-fast-path | 0.1 min |
| cohomology-candidate-proof | failed | check-original-proof | 0.0 min |
| cohomology-candidate-forced | failed | check-original-forced | 0.0 min |
| cohomology-candidate-proof2 | complete | check-original-proof | 3.2 min |
| cohomology-candidate-forced2 | complete | check-original-forced | 3.3 min |
| cohomology-conversion-entries | complete | trace-original-with-diagnostic-900s-limit | 5.0 min |
| cohomology-probe-build | complete | build-diagnostic-probe-controls | 1.1 min |
| cohomology-probe-small | complete | check-unchanged-original-at-180s | 3.7 min |
| cohomology-probe-complete | complete | check-unchanged-original-at-180s | 3.7 min |
| cohomology-no-app-cache | complete | check-unchanged-original-at-180s | 3.7 min |
| cohomology-trace-fallback | complete | trace-selected-ordinary-conversion | 3.2 min |
| cohomology-projection-build | complete | cohomology-projection-build | 1.3 min |
| cohomology-projection-fallback | complete | cohomology-projection-fallback | 4.8 min |
| cohomology-large-memo | complete | cohomology-large-memo | 3.2 min |
| cohomology-recovery-build | complete | cohomology-recovery-build | 0.0 min |
| cohomology-recovery-exact | complete | cohomology-recovery-exact | 11.7 min |
| cohomology-recovery-controls | complete | cohomology-recovery-controls | 1.4 min |
| cohomology-recovery-reload | complete | cohomology-recovery-reload | 3.9 min |
| cohomology-recovery-resume | failed | resume-scoped-survey-and-five-workers | 246.0 min |
| flasque-slice | complete | original-proof-preserving-slice | 8.4 min |
| flasque-baseline | complete | flasque-baseline | 15.4 min |
| flasque-small | complete | flasque-small | 6.4 min |
| flasque-local | complete | flasque-local | 0.7 min |
| flasque-diagnostic-build | complete | flasque-diagnostic-build | 1.0 min |
| flasque-context | complete | flasque-context | 0.4 min |
| Flasque bounded-conversion diagnosis | complete | flasque-diagnostics | 0.7 min |
| flasque-exact | complete | flasque-exact | 0.7 min |
| flasque-focused | complete | flasque-focused | 0.4 min |
| flasque-reload | complete | flasque-reload | 2.4 min |
| flasque-resume | failed | resume-from-80m-and-five-workers | 40.8 min |
| name-cases | complete | name-cases | 0.2 min |
| name-reload | complete | name-reload | 2.4 min |
| name-resume | failed | resume-from-80m-and-five-workers | 194.5 min |
| Thirty admitted theorem diagnostics | complete | instrument-thirty-admissions | 21.2 min |

## Parallel investigation

Diagnostic workers use independent memory-limited scopes alongside discovery.
Report: `/home/theo/Documents/github/rocq-lean-typechecker/work/mathlib-survey-investigation-20260920/README.md`.
These replays check original bodies while earlier survey admissions remain assumptions.
- replays-baseline-1/worker-1: finished; 2 passed, 1 timed out, 0 rejected.
- replays-baseline-1/worker-2: finished; 2 passed, 1 timed out, 0 rejected.
- replays-baseline-1/worker-3: finished; 4 passed, 1 timed out, 0 rejected.
- replays-baseline-1/worker-4: finished; 1 passed, 2 timed out, 0 rejected.
- replays-baseline-1/worker-5: finished; 1 passed, 2 timed out, 0 rejected.
- controls-1/cyclotomic-no-backtraces: finished; 0 passed, 1 timed out, 0 rejected.
- controls-1/projective-no-backtraces: finished; 0 passed, 1 timed out, 0 rejected.
- controls-1/projective-plain-oracle: finished; 0 passed, 1 timed out, 0 rejected.

The historical laptop prefix was 55,000,000 / 100,001,405 records.
That checkpoint was not transferred. Record counts are not theorem counts.

The head-beta candidate passed both Penrose replays, the Padic control, and independent target-only checks.
The preceding proof is retained as a separate regression control.


Current import: record None; `None`; phase complete.
Generation: `/media/theo/68998cde-9250-435b-ae2b-5122d9c4b9af/home/theo/Documents/rocq-mathlib-homepc-20260919/strict-lean-align-20260924d`.
- Replay baseline-prefix: saved; record 335176; `_private.Init.Data.String.Decode0.utf8DecodeChar__q_append_eq_assemble_UU2083_._proof_2`
- Replay baseline-proof: saved; record 348880; `_private.ProofWidgets.Component.PenroseDiagram0.ProofWidgets.Penrose.Diagram._proof_1`
- Replay baseline-target: deliberately stopped diagnostic; record 348894; `ProofWidgets.Penrose.Diagram`
- Replay candidate-crash-diagnostic: failed; record 348894; `ProofWidgets.Penrose.Diagram`
- Replay candidate-prefix: saved; record 348869; `ProofWidgets_Penrose_DiagramProps.(field).embeds`
- Replay candidate-proof: saved; record 348880; `_private.ProofWidgets.Component.PenroseDiagram0.ProofWidgets.Penrose.Diagram._proof_1`
- Replay candidate-target: failed; record 348894; `ProofWidgets.Penrose.Diagram`
- Replay context-sharing-prefix: saved; record 347203; `Std.TreeMap.Raw`
- Replay context-sharing-proof: saved; record 348880; `_private.ProofWidgets.Component.PenroseDiagram0.ProofWidgets.Penrose.Diagram._proof_1`
- Replay context-sharing-target: saved; record 348894; `ProofWidgets.Penrose.Diagram`
- Replay stack-safe-prefix: saved; record 327148; `ByteArray.utf8DecodeChar__q_eq_utf8DecodeChar__q_extract`
- Replay stack-safe-proof: saved; record 348880; `_private.ProofWidgets.Component.PenroseDiagram0.ProofWidgets.Penrose.Diagram._proof_1`
- Replay stack-safe-target: saved; record 348894; `ProofWidgets.Penrose.Diagram`

## Logs and inspection

- Rocq + stdlib + importer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/runtime/04-importer.log`
- Pinned Mathlib export log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/reference-2/02-verify.log`
- Large SSD transfer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/storage/01-move-reference-to-ssd.log`
- Fresh runtime qualification log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/qualification-3/05-receipt.log`
- Proof-preserving reproducer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/slice-3/01-penrose-definition-slice.log`
- Penrose baseline replay: baseline-target exited 255; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/replay-3/03-baseline-target.log
- Penrose baseline replay log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/replay-3/03-baseline-target.log`
- Prior Padic regression slice log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/padic-slice/01-padic-proof-slice.log`
- Small widget conversion diagnostics: synthetic-3000 exited 124; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/synthetic-baseline2/03-synthetic-3000.log
- Small widget conversion diagnostics log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/synthetic-baseline2/03-synthetic-3000.log`
- Head-beta candidate build and qualification log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/candidate3/11-synthetic-3000.log`
- Exact candidate replays and independent checks log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/candidate-replay3/08-independent-padic.log`
- Full Mathlib import (after qualification): full-mathlib-import exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/production3/02-full-mathlib-import.log
- Full Mathlib import (after qualification) log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/production3/02-full-mathlib-import.log`
- Exact crash diagnosis: capture-exact-crash exited 255; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/crash-diagnostic-job/01-capture-exact-crash.log
- Exact crash diagnosis log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/crash-diagnostic-job/01-capture-exact-crash.log`
- New colimit/limit timeout reproducer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/colimit-slice/01-proof-preserving-colimit-slice.log`
- Binder-context repair build and tests log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/colimit-build/11-synthetic-3000.log`
- Colimit repair exact and regression checks log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/colimit-replay/11-independent-padic.log`
- Full Mathlib resume from 20M after qualification: qualify-migrate-resume-from-20m exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/production7/01-qualify-migrate-resume-from-20m.log
- Full Mathlib resume from 20M after qualification log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/production7/01-qualify-migrate-resume-from-20m.log`
- Fresh 20M reload with repaired runtime log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/checkpoint20m-compat3-job/01-fresh-load-original-20m.log`
- Lie trace timeout reproducer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lie-trace-slice/01-proof-preserving-lie-trace-slice.log`
- Lie trace baseline replay: baseline-target exited -15; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lie-trace-replay/02-baseline-target.log
- Lie trace baseline replay log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lie-trace-replay/02-baseline-target.log`
- Exploratory survey and five-worker baseline: discover-and-five-worker-regressions exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey/02-discover-and-five-worker-regressions.log
- Exploratory survey and five-worker baseline log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey/02-discover-and-five-worker-regressions.log`
- Survey restart with opaque-state rollback fix: discover-and-five-worker-regressions exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey2/02-discover-and-five-worker-regressions.log
- Survey restart with opaque-state rollback fix log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey2/02-discover-and-five-worker-regressions.log`
- Survey restart after external-worker interruption: discover-and-five-worker-regressions exited -15; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey2-resume1/01-discover-and-five-worker-regressions.log
- Survey restart after external-worker interruption log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey2-resume1/01-discover-and-five-worker-regressions.log`
- Concurrent guard validation and survey continuation from 20M: discover-and-five-worker-regressions exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-concurrent1/02-discover-and-five-worker-regressions.log
- Concurrent guard validation and survey continuation from 20M log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-concurrent1/02-discover-and-five-worker-regressions.log`
- Admission recovery failure reproducer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-slice/01-proof-preserving-recovery-slice.log`
- Admission recovery baseline log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-baseline/01-reproduce-admission-timeout.log`
- Admission recovery candidate controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-validation/01-native-recovery-controls.log`
- Admission recovery candidate replay log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-candidate/01-candidate-admission-replay.log`
- Recovery candidate original 20M reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-reload/01-candidate-20m-reload.log`
- Exact statement admission comparison: exact-statement-admission-comparison exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-statement/01-exact-statement-admission-comparison.log
- Exact statement admission comparison log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-statement/01-exact-statement-admission-comparison.log`
- Exact statement admission comparison (corrected name metadata) log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-statement2/01-exact-statement-admission-comparison.log`
- Recovery conventional conversion control log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-plain/01-plain-oracle-recovery-control.log`
- Recovery projection-first conversion control log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-recovery-projection/01-projection-first-recovery-control.log`
- Projection-first native and negative controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-projection-validation/01-qualify-projection-first.log`
- Projection-first prior 15 targets (five workers) log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-projection-regressions/01-qualify-projection-first.log`
- Projection-first exact proof, independent check and 20M reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-projection-qualification/01-proof-recovery-independent-and-20m-controls.log`
- Qualified projection strategy and survey continuation from 20M: discover-and-five-worker-regressions exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-projection/03-discover-and-five-worker-regressions.log
- Qualified projection strategy and survey continuation from 20M log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-projection/03-discover-and-five-worker-regressions.log`
- ProofWidgets dependency audit and exclusion: audit-and-filter-proofwidgets exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/proofwidgets-filter/01-audit-and-filter-proofwidgets.log
- ProofWidgets dependency audit and exclusion log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/proofwidgets-filter/01-audit-and-filter-proofwidgets.log`
- ProofWidgets completed module inventory and dependency audit log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/proofwidgets-filter2/01-audit-and-filter-proofwidgets.log`
- ProofWidgets exclusion native proof and checkpoint controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/proofwidgets-controls/01-native-scope-controls.log`
- ProofWidgets-excluded survey from 40M and five-worker regressions: resume-control-scoped-survey exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-no-proofwidgets/03-resume-control-scoped-survey.log
- ProofWidgets-excluded survey from 40M and five-worker regressions log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-no-proofwidgets/03-resume-control-scoped-survey.log`
- Corrected survey-mode reload and scoped continuation: controls exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-scope-resume2/01-controls.log
- Corrected survey-mode reload and scoped continuation log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-scope-resume2/01-controls.log`
- Survey-mode admission controls, 40M reload and scoped continuation: discover exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-scope-resume3/04-discover.log
- Survey-mode admission controls, 40M reload and scoped continuation log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/survey-scope-resume3/04-discover.log`
- Lists.Equiv.casesOn failure slice and checked baseline: exact-baseline-replay exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lists-equiv-repro/02-exact-baseline-replay.log
- Lists.Equiv.casesOn failure slice and checked baseline log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lists-equiv-repro/02-exact-baseline-replay.log`
- Lists.Equiv recursor repair, qualified 40M continuation: resume-scoped-survey-and-five-worker-regressions exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lists-equiv-resume/03-resume-scoped-survey-and-five-worker-regressions.log
- Lists.Equiv recursor repair, qualified 40M continuation log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/lists-equiv-resume/03-resume-scoped-survey-and-five-worker-regressions.log`
- Mayer–Vietoris admission timeout proof-preserving slice log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-slice/01-proof-preserving-slice.log`
- Mayer–Vietoris checked baseline and native timeout samples log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-baseline/01-checked-prefix-and-exact-recovery-timeout.log`
- Mayer–Vietoris three bounded conversion comparisons log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-comparison/01-three-exact-proof-conversion-controls.log`
- Mayer–Vietoris surrounding definition regression slice log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-family/01-proof-preserving-sequence-family.log`
- Mayer–Vietoris conversion trace log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-trace/01-trace-kernel-conversion-entries.log`
- Mayer–Vietoris bounded congruence candidate build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-build/01-isolated-kernel-and-importer-build.log`
- Mayer–Vietoris candidate exact proof and statement admission log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-candidate/02-exact-statement-forced-admission.log`
- Mayer–Vietoris family, independent and focused regressions: qualify exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification/01-qualify.log
- Mayer–Vietoris family, independent and focused regressions log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification/01-qualify.log`
- Mayer–Vietoris candidate 16 survey controls: validate_survey exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-survey-controls/01-validate_survey.log
- Mayer–Vietoris candidate 16 survey controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-survey-controls/01-validate_survey.log`
- Mayer–Vietoris candidate original 40M reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-reload/01-check_reload.log`
- Mayer–Vietoris candidate five-worker prior target regressions: Prerequisite did not pass: /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-survey-controls/status.json
- Mayer–Vietoris corrected family and focused qualification: qualify2 exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification2/01-qualify2.log
- Mayer–Vietoris corrected family and focused qualification log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification2/01-qualify2.log`
- Mayer–Vietoris survey controls with original formal libraries log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-survey-controls2/01-validate_survey2.log`
- Mayer–Vietoris prior targets after corrected controls: five-workers-check-prior-17-cases exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-prior-targets2/01-five-workers-check-prior-17-cases.log
- Mayer–Vietoris prior targets after corrected controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-prior-targets2/01-five-workers-check-prior-17-cases.log`
- Mayer–Vietoris complete focused comparison against producer log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-focused/01-focused-old-new-comparison.log`
- Mayer–Vietoris complete qualification and independent check log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification-complete/01-collect-successes-and-independent-check.log`
- Mayer–Vietoris matched old/new cyclotomic timing log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-cyclotomic-comparison/01-matched-old-new-proof-replay.log`
- Mayer–Vietoris candidate limiting only unbounded fallback log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-build2/01-bounded-fallback-native-build.log`
- Narrowed candidate original proof and admission log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-candidate2/02-exact-statement-admission.log`
- Narrowed candidate family, focused and proof regressions: qualify exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification3/01-qualify.log
- Narrowed candidate family, focused and proof regressions log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification3/01-qualify.log`
- Narrowed candidate 16 survey controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-survey-controls3/01-controls.log`
- Narrowed candidate original 40M reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-reload2/01-reload.log`
- Narrowed candidate 17 historical target regressions: five-workers exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-prior-targets3/01-five-workers.log
- Narrowed candidate 17 historical target regressions log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-prior-targets3/01-five-workers.log`
- Qualified Mayer–Vietoris repair and survey continuation from 40M: Prerequisite did not pass: /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-qualification3/status.json
- Matched old/new 17 proof cases at unchanged 180s limit log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-matched/01-matched-seventeen-old-new-cases.log`
- Qualified congruence-work repair and survey continuation: resume-scoped-survey-and-five-workers exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-resume2/03-resume-scoped-survey-and-five-workers.log
- Qualified congruence-work repair and survey continuation log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/mayer-resume2/03-resume-scoped-survey-and-five-workers.log`
- JSON surrogate memory failure: original proof-preserving slice log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-slice/01-proof-preserving-slice.log`
- JSON surrogate: checked dependency prefix and native baseline log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-baseline/01-original-dependency-prefix-and-definition.log`
- JSON surrogate: three existing conversion-strategy controls: three-existing-conversion-strategies exited -15; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-comparison/01-three-existing-conversion-strategies.log
- JSON surrogate: three existing conversion-strategy controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-comparison/01-three-existing-conversion-strategies.log`
- JSON surrogate: three strategy controls, projection flag actually unset log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-comparison2/01-three-existing-conversion-strategies.log`
- JSON surrogate: candidate delayed constructor-demand kernel build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-build/01-isolated-delta-order-kernel-and-importer.log`
- JSON candidate: original failing definition and previous Mayer proof log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-candidate/01-original-json-definition-and-mayer-proof.log`
- json-focused: json-focused exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-focused/01-json-focused.log
- json-focused log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-focused/01-json-focused.log`
- json-reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-reload/01-json-reload.log`
- json-survey-controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-survey-controls/01-json-survey-controls.log`
- json-diagnostic-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-diagnostic-build/01-json-diagnostic-build.log`
- json-prior-targets: json-prior-targets exited -15; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-prior-targets/01-json-prior-targets.log
- json-prior-targets log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-prior-targets/01-json-prior-targets.log`
- JSON candidate: Mayer family, independent checks and prior proofs log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-qualification/01-family-independent-and-previous-proofs.log`
- json-build2 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-build2/01-json-build2.log`
- json-candidate2: json-candidate2 exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-candidate2/01-json-candidate2.log
- json-candidate2 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-candidate2/01-json-candidate2.log`
- json-build3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-build3/01-json-build3.log`
- json-candidate3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-candidate3/01-json-candidate3.log`
- json-focused3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-focused3/01-json-focused3.log`
- json-reload3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-reload3/01-json-reload3.log`
- json-survey-controls3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-survey-controls3/01-json-survey-controls3.log`
- json-qualification3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-qualification3/01-json-qualification3.log`
- json-diagnostic-build3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-diagnostic-build3/01-json-diagnostic-build3.log`
- json-prior-targets3 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-prior-targets3/01-json-prior-targets3.log`
- JSON repair qualification and survey continuation: resume-scoped-survey-and-five-workers exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-resume/03-resume-scoped-survey-and-five-workers.log
- JSON repair qualification and survey continuation log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/json-resume/03-resume-scoped-survey-and-five-workers.log`
- cohomology-slice log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-slice/01-proof-preserving-slice.log`
- cohomology-baseline log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-baseline/01-original-proof-and-admission.log`
- cohomology-stacks log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-stacks/01-sample-traced-target-only.log`
- cohomology-comparison log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-comparison/01-compare-original-proof-strategies.log`
- cohomology-diagnostic-build: build-stage-tracing-importer exited 2; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-diagnostic-build/01-build-stage-tracing-importer.log
- cohomology-diagnostic-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-diagnostic-build/01-build-stage-tracing-importer.log`
- cohomology-diagnostic-build2 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-diagnostic-build2/01-build-stage-tracing-importer.log`
- cohomology-inductive-trace log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-inductive-trace/01-trace-record-registration.log`
- cohomology-monoidal: check-small-monoidal-specialization exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-monoidal/01-check-small-monoidal-specialization.log
- cohomology-monoidal log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-monoidal/01-check-small-monoidal-specialization.log`
- cohomology-monoidal2 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-monoidal2/01-check-small-monoidal-specialization.log`
- cohomology-no-sharing log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-no-sharing/01-original-proof-without-reduction-sharing.log`
- cohomology-candidate-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-build/01-build-empty-universe-projection-fast-path.log`
- cohomology-candidate-proof: check-original-proof exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-proof/01-check-original-proof.log
- cohomology-candidate-proof log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-proof/01-check-original-proof.log`
- cohomology-candidate-forced: check-original-forced exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-forced/01-check-original-forced.log
- cohomology-candidate-forced log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-forced/01-check-original-forced.log`
- cohomology-candidate-proof2 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-proof2/01-check-original-proof.log`
- cohomology-candidate-forced2 log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-candidate-forced2/01-check-original-forced.log`
- cohomology-conversion-entries log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-conversion-entries/01-trace-original-with-diagnostic-900s-limit.log`
- cohomology-probe-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-probe-build/01-build-diagnostic-probe-controls.log`
- cohomology-probe-small log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-probe-small/01-check-unchanged-original-at-180s.log`
- cohomology-probe-complete log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-probe-complete/01-check-unchanged-original-at-180s.log`
- cohomology-no-app-cache log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-no-app-cache/01-check-unchanged-original-at-180s.log`
- cohomology-trace-fallback log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-trace-fallback/01-trace-selected-ordinary-conversion.log`
- cohomology-projection-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-projection-build/01-cohomology-projection-build.log`
- cohomology-projection-fallback log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-projection-fallback/01-cohomology-projection-fallback.log`
- cohomology-large-memo log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-large-memo/01-cohomology-large-memo.log`
- cohomology-recovery-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-recovery-build/01-cohomology-recovery-build.log`
- cohomology-recovery-exact log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-recovery-exact/01-cohomology-recovery-exact.log`
- cohomology-recovery-controls log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-recovery-controls/01-cohomology-recovery-controls.log`
- cohomology-recovery-reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-recovery-reload/01-cohomology-recovery-reload.log`
- cohomology-recovery-resume: resume-scoped-survey-and-five-workers exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-recovery-resume/03-resume-scoped-survey-and-five-workers.log
- cohomology-recovery-resume log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/cohomology-recovery-resume/03-resume-scoped-survey-and-five-workers.log`
- flasque-slice log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-slice/01-original-proof-preserving-slice.log`
- flasque-baseline log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-baseline/01-flasque-baseline.log`
- flasque-small log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-small/01-flasque-small.log`
- flasque-local log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-local/01-flasque-local.log`
- flasque-diagnostic-build log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-diagnostic-build/01-flasque-diagnostic-build.log`
- flasque-context log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-context/01-flasque-context.log`
- Flasque bounded-conversion diagnosis log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-diagnostics/01-flasque-diagnostics.log`
- flasque-exact log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-exact/01-flasque-exact.log`
- flasque-focused log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-focused/01-flasque-focused.log`
- flasque-reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-reload/01-flasque-reload.log`
- flasque-resume: resume-from-80m-and-five-workers exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-resume/03-resume-from-80m-and-five-workers.log
- flasque-resume log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/flasque-resume/03-resume-from-80m-and-five-workers.log`
- name-cases log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/name-cases/01-name-cases.log`
- name-reload log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/name-reload/01-name-reload.log`
- name-resume: resume-from-80m-and-five-workers exited 1; inspect /home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/name-resume/03-resume-from-80m-and-five-workers.log
- name-resume log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/name-resume/03-resume-from-80m-and-five-workers.log`
- Thirty admitted theorem diagnostics log: `/home/theo/Documents/github/rocq-lean-typechecker/work/homepc-20260919/blockers-diagnostics/01-instrument-thirty-admissions.log`

```sh
python3 scripts/managed_job.py status --directory work/homepc-20260919
```

## Storage and monitoring

Main disk free: 2.8 GiB.
Selected 4-TB SSD mounted: True. Data directory: `/media/theo/68998cde-9250-435b-ae2b-5122d9c4b9af/home/theo/Documents/rocq-mathlib-homepc-20260919`.
SSD free: 2829.9 GiB.

Local services update this page every 15 seconds without model calls.
Full logs and per-stage timing stay on disk. Agent log reads are bounded and event driven.
Failed prerequisites stop dependent work; proof policy is never relaxed automatically.

Stopped at83,122,651 with a type mismatch in TopCat.Sheaf.IsFlasque.epi_of_shortExact. Saved80M checkpoint has28 admissions. New proof-preserving investigation; immutable recovery-budget runtime retained.
23 Sep: generic environment-type rebasing repair qualified: original Flasque proof and independent checker pass; 20 focused controls show no new regressions; unchanged 80M reload and production wrapper pass. Survey resumed from 80M with 28 saved admissions.
23 Sep: small importer-only name encoding repair qualified (392 cases, original declaration, collision controls, checkpoint reload, independent and production-wrapper checks). Kernel unchanged. Survey resumed from 80M; the 85.03M failure was a backtick identifier.
24 Sep: admission-free strict import (candidate kernel v5, content-addressed closure cells + canonical memo, no projection-first) checked records 1-30,000,000 (three sealed checkpoints, work/mathlib-lean-align-20260923/data/strict-1) and stopped at 30,778,865 (Char.succ?._proof_1: stack overflow, a regression of the Sept-22 json-major-order change; records 20M-40M had only been checked by the older survey kernel). Diagnosed as a missing Lean rule (iota before delta: a recursor application whose major computes to a constructor is reduced before any delta choice); dev v9 adds a bounded major probe. Gates running: fixtures 33/33 pass, JSON parser case 4.0 s, 36-instance sweep and historical slices in progress. Details: work/mathlib-lean-align-20260923/README.md.
24 Sep 01:03: admission-free import restarted from record 1 as generation strict-lean-align-20260924 (dev kernel v9: bounded major probe; gates: fixtures 33/33, historical slices/fixtures no new failures, JSON 4 s, Char.succ record passes from the sealed 30M checkpoint). Sequential, 10M-record chunks (~75 min each in attempt 1), systemd unit mathlib-strict-lean-align-20260924. Progress: work/mathlib-lean-align-20260923/data/strict-2/progress.json.
24 Sep 02:48: admission-free import restarted from record 1 with dev kernel v10 (generation strict-lean-align-20260924b, unit mathlib-strict-lean-align-20260924b). v10 = v9 + memoized, cell-sharing nested conversions for definitional-K checks (pseudofunctor._proof_7 at record 68.9M: 900 s timeout -> 18 s). Gates: fixtures 33/33, historical slices 8/8, and for the first time all 36 admitted instances pass one 300 s sweep. The v9 generation (1 sealed chunk) is stopped and preserved.
24 Sep 03:30: admission-free import restarted from record 1 with dev kernel v11 (generation strict-lean-align-20260924c, unit mathlib-strict-lean-align-20260924c). v11 = v10 + fix of a kernel anomaly found by the v9 pre-validation at record 53,910,405 (the neutral fast path of whd_stack left content-shared cells locked; it now discharges its update frames). Gates: fixtures 33/33, slices 8/8, sweep 35/36 at 300 s under full load (the miss is the 283 s straggler). The v10 generation (no sealed chunk) is stopped.
24 Sep 03:45: attempt 4 (v11) stopped: an adversarial review of the v6-v10 kernel delta confirmed a soundness hole in the nested-conversion memo added in v10 (root memo entries ignored the ambient depth; an invalid refl was accepted by v10/v11, rejected by v5). v12 (lean-align-dev4-20260924) fixes it plus four review findings; the reproducer is now a permanent fixture (34/34 pass). v12 gates (slices, sweep) are running; attempt 5 starts when they pass.
24 Sep 03:58: admission-free import attempt 5 started from record 1 with dev kernel v12 (generation strict-lean-align-20260924d, unit mathlib-strict-lean-align-20260924d). v12 gates: fixtures 34/34 (incl. the new soundness reproducer), historical slices 8/8, JSON 8.7 s, Char.succ 5 s, sheaf-monoidal anomaly slice 12.9 s, pseudofunctor 23.5 s, sweep 36/36. v9 survey-mode pre-validation of 20M-100M found only the two already-repaired records; the 53.9M-60M tail is being re-validated with v12.
24 Sep 05:00: independent re-check: rocqchk (v12 build) passes the sealed 10M-record checkpoint of attempt 1 in 31 min (4.7 GiB); assumptions are exactly Lean's propext/Classical.choice/Quot.sound plus Rocq's primitive-integer axioms. Every chunk of attempt 5 is now re-checked by rocqchk as it seals (unit rocqchk-strict-lean-align-20260924d, results in work/mathlib-lean-align-20260923/data/rocqchk-strict-5).
24 Sep 06:05: pre-validation complete: records 20M-100M scanned in survey mode (v9 for 20M-40M, 60M-100M; v12 for 40M-60M) with no remaining timeout or error on the current kernel. Attempt 5 (v12) sealed chunk 1 (rocqchk exit 0) and is in chunk 2.
24 Sep 10:55: per-chunk rocqchk re-checks discontinued at the user's request (chunks 1-2 had passed); the sequential v12 import continues unaffected (chunk 7 of 10 in progress).
24 Sep 15:24: ADMISSION-FREE IMPORT COMPLETE. Generation strict-lean-align-20260924d (kernel v12) imported all 100,001,405 records of the scoped export in strict mode with no admission, no error and no timeout: 10 sealed chunks, 11.44 h of single-core time (05:03-15:24). Scope: ProofWidgets/widget UI declarations excluded by the scoped export (record numbers preserved); not a pass of the unchanged full export. Evidence and the per-declaration Lean-vs-Rocq comparison: work/mathlib-lean-align-20260923/README.md.
