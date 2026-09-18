# Substituted dependency probes: `String.utf8EncodeChar.eq_def`

This repairs the timeout reported at full-export line **641,616**. The full
pass was not repeated. `Utf8Encode.lean-export` contains the original Lean
declaration and only its dependencies: 8,452 lines / 166,035 bytes, exported
from `Init.Data.String.Decode` with Lean 4.27.0-rc1. No library proof is edited
or replaced.

## Cause and change

`Fresh.baseline.run.log` reproduces the timeout in the dependency-only import
with a 30-second line limit. Type and proof translation take about 0.002 CPU
seconds and universe processing another 0.019 seconds. Kernel conversion of
the original reflexivity proof then times out. `Prefix.baseline` saves the
dependencies; `Target.entries` and `Target.trace` isolate conversion call 216
after reloading that prefix.

Conversion compares the source UTF-8 function with its unfolded body. The
existing unfolding dependency probe cannot inspect closures with nonidentity
term substitutions. It also discards a positive witness when the reverse
probe is inconclusive. Consequently, conversion unfolds the nested conditional
and open arithmetic computations instead of their wrappers. The baseline
trace reaches millions of comparison steps without resolving the equality.

The only implementation change is in the live kernel's `kernel/conversion.ml`:

- Extend the existing bounded, read-only dependency probe to inspect only
  referenced entries of saved term substitutions. Reuse the existing
  `CClosure.inspect_substituted_rel`; do not reify, reduce, lift-copy or mutate
  closures. Traverse raw terms with binder depth and account for lambda domains
  in their existing outermost-first order.
- Apply the same traversal during the existing update-alias check, before
  accepting a dependency witness. Keep the 1,024-visit shared budget and
  conservative refusal for unresolved substitutions and unsupported forms.
- Let a positive dependency witness choose the next delta step when the reverse
  probe is unknown. This is an unfolding preference only; ordinary conversion
  still checks the resulting terms.

The initial two-arm preference change alone still timed out (`Target.one-sided`).
Adding substitution inspection resolves the arithmetic wrapper comparison.
`Target.substitution-trace` passes: call 216 finishes before trace step 430,
and the formerly unknown pair at step 69 becomes a true/false dependency pair.
The saved baseline prefix is unchanged during this diagnostic check.

`conversion.ml.before` captures the source before this repair, including all
pre-existing worktree edits. Compare it with the live file to review this
repair alone. No importer, foundation, arithmetic rule, registration validator
or conversion acceptance rule is changed.

## Commands and validation

Export the unchanged target under the existing memory guard:

```sh
ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152 \
ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0 \
bash work/run-memory-guarded.sh \
  timeout --signal=TERM --kill-after=5s 180 \
  bash work/utf8-encode-eq-def-repro/export.sh
```

The adjacent export uses the same command with these arguments to `export.sh`:

```text
Adjacent String.length_utf8EncodeChar String.utf8EncodeChar_eq_utf8EncodeCharFast
```

The retained baseline and diagnostic runs used:

```sh
LEAN_IMPORT_DECLARE_TRACE_LINE=8452 \
  bash work/utf8-encode-eq-def-repro/run.sh Fresh baseline
bash work/utf8-encode-eq-def-repro/run.sh Prefix baseline
ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES=1 \
LEAN_IMPORT_DUMP_FAILED_DEF=String.utf8EncodeChar.eq_def \
  bash work/utf8-encode-eq-def-repro/run.sh Target entries
ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL=216 \
  bash work/utf8-encode-eq-def-repro/run.sh Target trace
ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL=216 \
  bash work/utf8-encode-eq-def-repro/run.sh Target substitution-trace
```

The first four commands precede the repair; the last uses the repaired worker.
Run tags are unique and preserve earlier logs.

Build and run focused checks sequentially:

```sh
bash work/utf8-encode-eq-def-repro/build.sh
bash work/utf8-encode-eq-def-repro/run-focused.sh final
```

The build is guarded and limited to one dune job and 300 seconds. Each focused
compiler uses the existing atomic runner: 2 GiB hard memory, 1.75 GiB RSS,
6 GiB available-memory reserve, no workload swap, 8 MiB stack, 180-second
process limit. The owner service is inherited. Imported declarations have a
30-second line limit. No limits were raised to obtain a pass.

`Fresh` checks all target dependencies and the target. `Prefix`/`Target` check
the same target after a separate dependency save/reload. `Adjacent` checks
the original length and fast-encoder equivalence proofs. `Reload` loads the
freshly checked modules. `SubstitutionDependency` exercises open arguments,
nested and dependent lambdas, and shared let substitutions; its negative
controls require kernel rejection of two unequal results and an opaque
function. Its `exact_no_check` tactic only defers elaboration: `Qed` performs
kernel checking, and rejected negative proofs are aborted without declarations.

Run the unchanged broader gate without creating a checkpoint generation:

```sh
python3 scripts/checkpoint_generation.py \
  --foundation /home/theo/Documents/github/rocq-lean-typechecker/work/cslib-loop/20260908T055032055969/validation-retry/generation/foundation/Lean.vo \
  --directory /home/theo/Documents/github/rocq-lean-typechecker/work/utf8-encode-eq-def-repro/regressions-substitution
```

The broader gate completed with exit 0: **58 compiler stages passed**, followed
by **169 unit tests, OK (two existing skips)**. See `regressions-substitution.log`
and `regressions-substitution/passed.json`. The maximum compiler cgroup peak was
306,836 KiB. The runner's checksum checks for its original regression inputs,
importer, foundation and worker all passed. Its fixture/unit-test log messages
about continuations are test output, not a real full-library run.

The gate tested worker `b79be10d53cee70f55f16fa77bbe0c980bd0cca982c5bcd7f4d2666462b821c3`.
Afterwards, two explanatory source comments were included in the final rebuild;
there is no executable logic change between the broad gate and final focused
tests.

All **six focused fixtures passed** with the final worker (`focused.final.log`):

- `Fresh`: 210 entries, including the unchanged failing declaration.
- `Prefix` and `Target`: separate dependency save, reload and target checking.
- `Adjacent`: 1,845 entries, including the unchanged
  `String.utf8EncodeChar_eq_utf8EncodeCharFast` and
  `String.length_utf8EncodeChar` proofs. This export has 136,662 lines /
  3,066,889 bytes.
- `SubstitutionDependency`: six positive kernel checks and three required
  kernel rejections, each under a five-second limit. The entire fixture took
  less than 1.3 seconds, so its negative controls did not pass by timing out.
- `Reload`: all newly saved target/adjacent modules load successfully.

The maximum final focused cgroup peak was **259,640 KiB**. The final guarded
worker build passed with a 310,304 KiB peak. Shell syntax and kernel
`git diff --check` checks also passed.

## Checkpoint compatibility

This is a kernel-only unfolding strategy repair. The importer, foundation and
stored representation remain unchanged: request **`checkpoint_action="reuse"`**
with **`foundation=""`**. The current foundation remains the one under
`work/cslib-loop/20260908T055032055969/validation-retry/generation/foundation/`.
No progress file was present when the active checkpoint directory was inspected.
The supervisor owns reload gates, full checking and all checkpoint saves.

Only after the final checks passed, the worker digest in
`work/unit-projection-repro/check-toolchain.sh` was updated. Its other digest
checks and the historical producer manifests remain unchanged. The final
importer and foundation hashes still match the initial values below.

These tests exercise the experimental kernel. They establish neither full
cslib success nor a soundness result. Reload checks compatibility, not every
stored proof. Historical checkpoints, seals and manifests are preserved.

```text
baseline worker: e690ad45a8bbc7b7e93aad63fa72e6a01126287e57c12b675c1f7d938a7ce6c3
final worker:    c63dba1923052ffb2beafba1b7496a489a6cb3fae59b212b9eb841bd2287d5a8
importer:        6304d147f1085e72463e7efc1d9bd9c2ff5920ddd95403102d2ca6f791a13bb1
foundation:      de89adf144ae8e96a8b20c0e30d435677ab8fb106c36906f9d9ebeaf5225a57b
target export:   d50c28ca643a437939538a6fbac5557e553ab74a72c193af559cf56c5aa33bb7
adjacent export: 754b1deadd33e8a3e7416c18d0dee484499a2c18d8e96b28af3aecc3ad83c181
```
