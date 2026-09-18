# Char ordinal conversion stall: diagnosis and bounded scheduling repair

Reported production declaration: line 30,805,408,
`_private.Init.Data.Char.Ordinal.0.Char.ofOrdinal_le_of_le._proof_1_6`.

## Cause

The proof contains reflected linear arithmetic about addition by 2048 and
remainder modulo 4294967296. Conversion was unfolding the integer/modulo side
while the opposite polynomial denotation waited on a constructor-driven
eliminator. The trace repeatedly entered `Int.emod`, `Int.add`, and natural
recursors. Large allocations and GC were consequences of this scheduling.

There were two missing cases in the existing eliminator preference:

1. A generated nonrecursive recursor has a `Case` body, not a `Fix` body.
2. Its actual major argument can be a local definition (or a local alias of
   one), rather than a constructor immediately visible in the closure.

The first change alone moved the failure to another comparison and still
timed out. Handling local definitions as well resolves the extracted theorem.
This is not evidence for restoring a quadratic dependency cache or increasing
the production timeout.

## Lean comparison

Compared the exact Lean 4.29 kernel at commit
`98dc76e3c0a9b856c9b98726b713fb04fab16740`, not the differently versioned local
development checkout. References are in
[Lean's type checker](https://github.com/leanprover/lean4/blob/98dc76e3c0a9b856c9b98726b713fb04fab16740/src/kernel/type_checker.cpp):

- `is_def_eq_core` performs core weak-head reduction before lazy delta.
- `whnf_core` dispatches primitive recursors; `reduce_recursor` reduces their
  major premise. Local definitions are followed by `whnf_fvar`.
- Only subsequently does lazy delta use definition hints and argument
  congruence. Lean also has literal arithmetic and WHNF caches, but adding
  another arithmetic fast path was not needed for this failure.

The adaptation restores the relevant scheduling priority for ordinary Rocq
constants wrapping translated recursors. It is not a wholesale replacement of
Rocq's conversion strategy, and does not claim every reduction step matches
Lean. In particular, existing dependency, projection, compact-number, and
sharing policies are retained when the new bounded observation is inconclusive.

## Implementation and safety boundaries

Only `kernel/conversion.ml` changed in the kernel during this repair:

- `constructor_eliminator_application` recognizes both lambda/Fix and
  lambda/Case wrappers and locates the actual structural/major argument.
- `visible_constructor_head` observes constructors, compact naturals,
  substitutions, and local-definition aliases without reducing or quoting
  arbitrary terms. Local context offsets are tracked arithmetically rather
  than lifting/copying a potentially huge definition body.
- The observation is used before same-head argument congruence and when
  choosing between two unfoldable heads. Original argument stacks are used;
  compact arithmetic probing may already have consumed the working stacks.
- Observation is bounded: depth 16, local index 4096, wrapper scan 64, stack
  scan 128. Unknown/neutral or excessively deep shapes decline the preference.
- The existing typed-conversion and dependency-heuristic flags gate it, and
  reduction transparency/oracle restrictions remain enforced.

This code chooses which ordinary unfolding to attempt. It cannot return a
successful equality judgment, erase a proof, alter universe checks, or bypass
opacity. It adds no cache and mutates no closure. Existing sharing,
application-domain caches, checker policy, and importer code are unchanged.

Pre-repair `conversion.ml` is preserved as Git blob
`6ce5c9d0698edcb3aba3ffa8b60ed0b472d1de96`. The worktree already contained
substantial earlier edits; those are not attributed to this repair.

## Reproduction and evidence

`slice.json` pins the source NDJSON, slicer, converter, and extracted outputs.
The slice keeps all dependency proofs: 138,247 selected NDJSON records, zero
abstracted proofs. The resulting import stream has 138,243 lines; its last
declaration is the reported target. `CharWhole.v` checks the complete slice
fresh, while `CharTarget.v` measures the target after a saved prefix.

| Target-only replay | Outcome | Process time | Guard cgroup peak |
| --- | --- | ---: | ---: |
| Baseline worker | declaration timeout at 120 s | 125.28 s | 14,421,352 KiB |
| Final worker | passed | 20.16 s | 1,224,516 KiB |

These are measured replay process times, not a claim about the full production
checkpoint's total memory or runtime. Hash-validation overhead is excluded.

Final worker SHA-256:
`80c4781a4738d0509f88630d70583415a93b8d88a1f15306561fd88c70e70940`.
Final independent checker SHA-256:
`07a7f6884cce5c79a25c2d50772e35b337038c8275b800a770b5ec601946ef6a`.

Validation completed serially under the existing resource guard; all 15 stages
passed. Authoritative completion evidence is `validation/passed.json`. The
batch covers:

- target and fresh complete Char slice, followed by independent checking;
- SSet, Lie, derivative, and the continuous original-order Riemannian range
  `[25000001,25525775)`, including independent checks;
- native, legacy, importer, runner/resource/checkpoint and private unit tests;
- ordinary and strict independent native checking, plus strict-policy cases.

Completed totals: 17 native fixtures, 20 legacy fixtures, 44 importer tests,
206 runner tests (2 explicit skips), all private unit families, and 11 strict
policy checks. The fresh import/checkpoint/seal/reload smoke test also passed.
The complete Char slice took 70.16 seconds in the worker and 21.87 seconds in
the independent checker. The original-order Riemannian continuation took
1119.28 seconds in the worker and 511.47 seconds in the independent checker;
the worker time is essentially unchanged from the previous successful replay.

One orchestration error is preserved rather than hidden: the batch supplied
an absolute path to the final strict-policy harness, whose CLI accepts only a
directory name. `finish-validation.py` verified all frozen inputs and the first
14 successful stages, then reran only that final stage with the correct
argument. Both the failed invocation and successful policy results remain in
the validation record. No kernel or test semantics changed for this retry.

The native fixture `abbrev_congruence_order.v` includes Fix and Case wrappers,
discarded expensive branches, local aliases, neutral-major and unequal-result
rejections, partial applications, and opacity. Private
`eliminator_head_test.ml` separately tests environment offsets, substitutions,
new binders, finite bounds, context separation, and non-mutation.

Independent Mathlib continuation checks reuse sealed dependencies explicitly
(`-norec`); they are not fresh independent rechecks of all earlier Mathlib.
The Char whole-slice check includes all extracted dependency proofs in its new
module. Strict native checks recheck their dependencies and explicitly enable
the project's definitional-UIP compatibility setting.

## Resumption

`resume.py` is a separate fail-closed promotion step, not part of the test
batch. It requires every stage to pass on the exact final binaries, validates
input and artifact hashes, checks the unchanged production cursor, and freezes
a new validation receipt and consumer certificate. Existing producer seals
are not rewritten.

It resumes `work/mathlib-alignment-5m-20260913-with-terminal` from the sealed
30M checkpoint (line 30,000,001), with the existing 5M checkpoint interval,
1800-second declaration timeout, and 16 GiB/no-swap guard. No diagnostic
conversion override is enabled. `resume-approval.json` records an actual
launch approval; its absence means production has not yet been launched by
this repair. Service startup must still be checked separately.

Release launched successfully at 2026-09-15 00:33:51 CEST as
`rocq-mathlib-alignment-5m-char-eliminator.service`; the service was confirmed
active/running (initial main PID 887638). The 30M checkpoint and reload artifact
hashes were checked against the saved cursor before launching. Release evidence
is frozen in `work/mathlib-char-eliminator-release-20260914/validation-receipt.json`;
the production certificate SHA-256 is
`49ba2b42fd7f53b296239b3b9f84b0657a1b9939232f0e35be4919b8f6595489`.

Full Mathlib verification remains incomplete until the production stream
reaches EOF (100,001,405 input lines). Passing these tests does not justify a
claim that no later performance or compatibility problem can occur. After
the startup check, the production loop is left running without assistant
monitoring, as requested.
