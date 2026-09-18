# WithTerminal regression, line 11,422,301

Reported declaration: `CategoryTheory.WithTerminal.instCategory._proof_2`.
The September 13 fresh Mathlib generation saved and reloaded 5M and 10M, then
failed here with an illegal application (not a timeout).

## Baseline and diagnosis

Baseline worker SHA256:
`b02396916069318a4fddd34514ecd937a5294a504384fee31caecfdb62888cb5`.
The pinned export and two original checkpoint seals are verified by `run.py`.
The producer importer is the unchanged isolated `../kernel-alignment-pass/importer.42J4K0w1`.

`families-baseline/result.json` records a real proof-checking failure (exit 1,
0.78 seconds) for `Families.v`: a bound value of type `family true`, where
`family b := if b then U else nat`, is not accepted as judgmentally equal to the
constructor of registered singleton `U`. The optional type inspector used to
decline all cases, including ordinary constructor matches needed to determine
this type. This is distinct from the earlier missing result-type witness for
a *stuck value-level case*.

## Candidate

The closure snapshot machine permits ordinary constructor cases under its
existing shared copying/head-step budget. Branch selection validates the
constructor/case boundary, charges arguments and branch declarations, and
charges parameter contexts incrementally when lazy let substitutions are
needed. Only the selected branch executes. Case inversion, fixpoints,
primitives and other previously unsupported computations still decline.
No external conversion hook is allowed to escape the inspection budget.
The singleton classifier enables iota as well as beta/zeta reduction, keeping
explicit alias transparency checks and full instantiated operand-type checks.

The native fixture is `test-suite/success/unit_like_type_families.v` in the
kernel worktree. The direct API fixture `unit_case_witness.ml` covers both
conversion entry points, both operand orders, local/named variables, and
different parameter instantiations that must not become equal. The snapshot
fixture covers lazy branch selection, budget exhaustion, isolated mutations,
and malformed/partial constructor boundaries.

## Executed validation

- Original-order baseline prefix 10,000,001–11,422,300: pass including save,
  2,053.64 s. Artifact SHA256
  `af46a1bc1a4b8fb582bbca6404a3fc8127e60b545b1477c4e469d77e6112d0c4`.
- Proof-preserving slice: 12,259 records, zero dependency proofs abstracted;
  `slice.json` pins the export, extractor, converter and outputs. The initial
  extraction's address-space limit was too small for the 5.3 GiB mmap; it was
  retried successfully under a 3 GiB resident-memory cgroup with a 10 GiB
  address-space cap. This was a harness issue, not a kernel result.
- `slice-baseline`: reproduces the exact reported declaration/illegal
  application in 9.36 s on `b0239691...`.
- New worker `938cf20b10fc8ebcde26d325e797057e79d59e42b1a2078613ff7f53222fe5ac`;
  checker `c0d1cfb3682ed761a8563e2b5e03a9886d191eda054c60e9691ee2856094840e`.
  `families-fixed` passes the expanded native fixture, including constructor lets.
- Updating CClosure's documented interface changes its compiler digest. The
  first `slice-fixed` attempt is an interface-mismatch **setup failure**, not a
  proof-checking result. Consumer importer `../kernel-alignment-pass/importer.lFy9zJVL`
  was rebuilt separately from unchanged sources; original checkpoint producer
  artifacts/manifests remain intact. The diagnostic harness pins both toolchains.
- `slice-fixed-2` passes the same proof-preserving slice including save in
  10.99 s. Artifact SHA256
  `60e8f2488551d139c8561dbd44daa4890a49938f580ddba024ae5a3d0aa31377`.
- Independent rechecking of the complete slice and its dependencies passes in
  the importer's existing compatibility profile; no `-admit` or `-norec`.
  Strict mode with explicit UIP **does not pass**: it refuses `Slice.autoParam`
  because the existing importer records definitions with elimination checking
  disabled (`with_unsafe_univs` in `src/lean.ml`). This repair neither introduces
  nor removes that relaxation. Compatibility success is not strict-theory
  certification. Both checker results and input hashes are retained in
  `slice-fixed-2/`.

- Full `../kernel-alignment-pass/final-gates-20` passes on the final worker:
  nine runtime-test families plus private API tests, 13 native fixtures, 20 legacy
  fixtures, 44 importer cases, fresh original-order smoke/save/reloads, and
  204 runner tests passed/two skipped.
- Independent native-fixture checks pass in compatibility (1.81 s) and strict
  with explicit UIP (1.77 s). All 11 strict checker CLI controls and the direct
  four-flag/UIP-policy test also pass (`strict-checker-5`). These native results
  are separate from the imported slice's strict-profile refusal above.

- Original-context replay 11,422,301–11,500,000 passes including save in 254.23 s;
  the reported theorem's declaration takes 0.108 CPU seconds after loading.
  `replay11500/ReplayTo11500000.vo` SHA256:
  `051013a2405312b9facda021e83dd2edbbdb68fa9d685bb37f455ab024683185`.
  This is a diagnostic continuation from the original sealed 10M chain and
  baseline prefix, not a promoted checkpoint for the new full generation.

- Fresh `reload11500` succeeds including save in 36.24 s, artifact SHA256
  `7df8997684463c3d7734fac12760d79928f7d7cbb0677dfe6f428dcd72ad3538`.

## Restart

The full line-1 run is in `../mathlib-alignment-5m-20260913-with-terminal`, service
`rocq-mathlib-alignment-5m-20260913-with-terminal.service`, with 5M checkpoints,
no seed, no proof skipping, and unchanged timeout/memory/disk limits. The old
generation and diagnostic checkpoints are retained, not used as new-run seeds.
Only startup is verified; no assistant monitoring/repair loop is scheduled.
Launch: September 13 at 15:05:19 Paris time; startup verified through line
85,111. Plan: 100,001,405 records, start=1, interval=5,000,000, seed=null.

Passing these tests does not establish full Mathlib acceptance or exact kernel equality.
