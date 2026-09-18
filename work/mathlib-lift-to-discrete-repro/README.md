# `liftToDiscrete._proof_5` regression — 13 September 2026

Target: original NDJSON line 5,816,190,
`_private.Mathlib.CategoryTheory.IsConnected0.CategoryTheory.IsPreconnected.IsoConstantAux.liftToDiscrete._proof_5`.

The fresh 5M-checkpoint generation failed here on worker
`3a9480ea6f86050019bf78e3be3c0dc254ccb96b4cad361e99af1e862dc637dd`.
Its 5M save and fresh reload passed. Earlier 20M+ diagnostic runs used different
builds; those runs are not evidence that this build checked that prefix.

## Reproductions

- `prefix`: original order from 5,000,001 through 5,816,189, including save,
  passed in 1,266.40 seconds. No proofs skipped. Artifact
  `9940f6d9bfc224dd2795974566f7097e5e790652c3b17ceb7c6687d2232da756`.
- `target-baseline`: the exact next theorem fails in 35.55 seconds after loading
  that prefix, matching the full generation's illegal-application error.
- `LiftToDiscrete.ndjson`: 17,052 dependency records, with ALL dependency proof
  bodies retained; no additional axioms. This is a sparse-ID diagnostic slice,
  not a directly loadable dense NDJSON export.
- `LiftToDiscrete.stream.lean-export`: successful streaming conversion of the
  slice to dense IDs. `slice-stream-baseline` reproduces the target failure at
  its final declaration, line 17,048, in 11.21 seconds.
- `slice-baseline` is a sparse-ID parser rejection, not the theorem failure.
  `slice-dense-baseline` consumed an incomplete non-streaming conversion and is
  explicitly INVALID as target-validation evidence.

## Candidate and scope

The strengthened common-type checks lacked result-type recovery for stuck
cases and case-inversion nodes. Recovering a singleton's family alone is not
enough: the full parameterized types must still be compared. The candidate
instantiates the return predicate with the actual scrutinee and indices, handles
let-bound context entries, and retains ordinary type comparison. It does not
evaluate the scrutinee to discover the return type or skip dependency proofs.

Identity relocations now retain closure data, including erased proof arguments,
instead of trying to quote it as ordinary syntax. Bounded snapshots isolate
optional type inspection. Nonidentity relocations retain the existing bounded
quotation path; this is not a completeness proof of all conversion heuristics.

New direct API tests reproduce the old stuck-case failure and check constant
and dependent indexed motives in both conversion APIs and both directions.
Mismatched parameters remain rejected. The existing unit witness, opacity,
saturation, projection-cache, quotation-budget and scheduling suites pass on
the source candidate.

## Rebuilt worker verification

Worker: `eef8700bf7866f3b04fcd27192b30c96bfe7d71227875a5ce72d001a8d61dfec`.
Checker: `a5394a51ecccf2b9654d8720c3c6fabbe00d39128db065d88177b1f821e0fd1b`.
The isolated importer is unchanged (`../kernel-alignment-pass/importer.42J4K0w1`).

- `slice-stream-candidate` passes the entire proof-preserving dependency slice
  and target in 13.42 seconds, including save. Artifact
  `f74be09adf522d049f7f8e4448ecbe2ecee437ebdaac4831288fa0edb8db3a0c`.
- `target-candidate` passes the exact original-order target after loading the
  full saved prefix in 117.05 seconds, including save. Artifact
  `a9e7b04566bbeb30f818ede07fa43d7ed25adb62a703747819ddbab35fee7735`.
  The declaration itself takes about 0.036 CPU seconds (logged start 23.817,
  done 23.853); prefix loading and serialization account for most replay time.
  Loading this prefix does not recheck its historical proofs; the independent
  small slice does check all its retained proofs on the repaired worker.
- Native `unit_like_cases.v` passes stuck ordinary cases, equality transports,
  two inlined inversion cases, nested record eta and relevant-data negatives.
- `final-gates-17` passes private/runtime tests and all 12 native fixtures, but
  stops in the legacy fixture setup: the old `MathlibTo1000000.vo` was deleted
  in the user-requested cleanup. This is not a completed gate. The validator now
  accepts an explicit sealed generation and records the producer/consumer
  hashes; only the two fixtures' imported module name is adapted.

- `through6m` reloads the repaired target and checks the following original
  declarations through line 6,000,000, then saves successfully in 173.05 seconds.
  Artifact `3edeb60bd8eb645ed5fec88e17700a40d1a30dad6cd9f492e29a11258eda96af`.
- Runner suite: 206 tests run, 204 passed, two skipped (13.50 seconds).

`final-gates-18` completes all nine existing runtime families, 12 native,
20 legacy and 44 importer fixtures, fresh smoke saves/reloads, and 206 runner
tests (two skipped). **Its independent native recheck then fails** in
`unit_like_cases.Unnamed_thm`: the generic conversion API's constructor
eligibility check still excludes a locally bound stuck case. The new
lambda-wrapped direct API positive reproduces that failure on `eef8700b...`.

## Generic-API follow-up

Worker: `b02396916069318a4fddd34514ecd937a5294a504384fee31caecfdb62888cb5`.
Checker: `b669eae049cf2396222f72c8719c18d34fa56dd560c4ce7f3cdb8c3e22a1cc0d`.

The two symmetric constructor branches now allow stuck eliminations to reach
the full-type witness even without the caller's typed-input hint. This grants
no equality by itself: singleton reclassification and full type comparison
still must pass. The lambda-wrapped positive and mismatched-parameter negative
now pass in both APIs against the rebuilt library.

Independent rechecking of all 12 gate-18 native artifacts now passes in both
compatibility (1.80 seconds) and strict (1.79 seconds) modes. The latter explicitly
allows the definitional-UIP bridge required by the EqS fixture; no dependencies
are admitted, and disabled checking flags remain rejected. Results:
`final-gates-18/generic-independent-check.json` and
`final-gates-18/generic-strict-independent-check.json` under the alignment workdir.

`final-gates-19` passes the complete rerun on `b0239691...`: nine existing
runtime families plus the expanded case API tests, 12 native fixtures, 20 legacy
fixtures, 44 importer cases, fresh smoke saves/reloads and 206 runner tests
(204 passed, two skipped). Its 12 newly generated native artifacts also pass
independent compatibility and strict-with-explicit-UIP checking (both 1.79 s).
The eleven strict-checker CLI controls pass in `strict-checker-4`; the direct
CheckFlags policy test, including elimination-check rejection, passes too.

`replay6m-final` passes original declarations 5,816,190 through 6,000,000 on the
final build, including save, in 170.77 seconds. Artifact
`2af142e1364f367bc24fcd97e20fd8eefcc1c7d9d1a2fee104267b64499e9615`.
The earlier prefix is loaded, not rechecked by this diagnostic.
`reload6m-final` passes a fresh worker load and save in 119.61 seconds; artifact
`3f093f939b427d726050607999b08256f1997461fe87de5759c4e533a170b1f5`.
Diagnostic snapshots are not promoted to the fresh run.

## Restart

The full Mathlib run was restarted from line 1 on 13 September at 10:51 Paris
time, in `../mathlib-alignment-5m-20260913`, user service
`rocq-mathlib-alignment-5m-20260913.service`. It uses the final worker above,
the unchanged isolated importer and a fresh foundation, no seed checkpoint,
5M checkpoint intervals, 1,800 seconds per declaration, 15 GiB RSS / 16 GiB
cgroup / zero swap. Existing failed-generation evidence is retained.

Read the new generation's `progress.json` and `latest/` logs. Only startup is
checked by the assistant; no ongoing assistant monitoring or repair is scheduled.
About 9 GiB remained free at launch, so the disk safety guard may stop the run
before EOF unless more space becomes available. Full Mathlib acceptance remains
unverified until this run completes successfully.

Mathlib's discrete composition explicitly eliminates an equality proof:
[pinned source](https://github.com/leanprover-community/mathlib4/blob/8a178386ffc0f5fef0b77738bb5449d50efeea95/Mathlib/CategoryTheory/Discrete/Basic.lean#L68).
This report does not claim exact kernel equivalence or full Mathlib acceptance.
