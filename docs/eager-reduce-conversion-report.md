# Rocq/Lean `eagerReduce` conversion gap

## Purpose of this report

This report is a design brief for solving the current cslib frontier in
`rocq-lean-import`. It records what is known, what has only been tried, and the
constraints that a real solution must satisfy. It does **not** present the
current experimental branch as a solution.

The requested outcome is a design, not an implementation.

## Executive summary

The current blocking declaration is Lean's generated termination proof

```text
Std.DTreeMap.Internal.Impl.link2._unary._proof_1
```

from `Std.Data.DTreeMap.Internal.Operations`.

This is not a missing mathematical theorem. Lean accepts a reflexivity proof
because the proof argument is wrapped in `eagerReduce`. That wrapper is
definitionally the identity, but the Lean kernel recognizes it specially and
temporarily changes its conversion strategy while checking that application
argument. The translated Rocq term retains only the ordinary identity
definition; it does not retain the kernel-level operational effect of the
marker. Stock Rocq can in principle reduce the same computation, but its
ordinary conversion check takes prohibitive time and memory on this real,
open, highly shared term.

An importer-side evaluator can reduce the relevant Boolean expression to
`true` in a few seconds. The unresolved problem is how to communicate that
result to Rocq in a compact, generic form that the stock Rocq kernel can check
independently and efficiently. Flat equality proofs and naïve checkpointing
destroy or repeat sharing; a zipper-based certificate also encounters genuinely
dependent projection contexts, where homogeneous congruence is not sufficient.

The central design question is therefore:

> How should an importer preserve the local meaning of Lean's `eagerReduce`
> while producing a small, replayable, sharing-preserving certificate accepted
> efficiently by the unmodified Rocq 9.3 kernel?

## Project objective and trust boundary

The larger project tests Lean libraries with Rocq:

```text
Lean library
  -> Lean Kernel Arena NDJSON
  -> legacy `lean-export`
  -> `rocq-lean-import`
  -> Rocq kernel verification
```

The target library is cslib, but the intended fix must be generic enough for
modern Lean libraries. In particular:

- no cslib theorem may be manually rewritten or reproved in Rocq;
- no declaration-specific name matching is acceptable;
- an OCaml computation performed by the importer must not simply be trusted;
- generated declarations must remain independently checkable from their
  `.vo` files;
- no axiom or unchecked reduction rule may silently enlarge the trusted base;
- an upstream patch should be small enough to explain and review.

A small Rocq-kernel change is not ruled out if it is the cleanest general
solution, but its semantics, persistence in compiled objects, soundness, and
review surface must be explicit. The preferred result uses stock Rocq 9.3 if
that is technically realistic.

## Pinned environment

The reference configuration is recorded in
`config/rocq-lean-import.lock.json`:

```text
Rocq:              9.3+rc1, commit f756383de2e66f63c95815c73838596d7d97c1c2
Rocq stdlib:       commit 3e47b26f345f36e375d81ade399eed0e310984b3
Importer baseline: commit 38fb4791bc7a3bc49995526448778c6e5555aaf1
Opam switch:       rocq93_clean
```

The clean cslib integration branch currently used for frontier testing is:

```text
_worktrees/rocq-lean-import/generic-cslib-current
branch: integration/generic-cslib-current
commit: 2fe11f4c304e13a854f855de0ad45311b6eca718
```

It contains the preceding generic importer fixes, including checked
certificates for several closed `Nat` operations and comparisons. Those fixes
advance cslib to the `link2` proof; they do not solve the open `eagerReduce`
case described here.

## Minimal Lean reproduction

The reproduction source is:

```text
_deps/lean-kernel-arena/tests/repros/dtree-link2-hconstr-timeout.lean
```

Its complete contents are:

```lean
import Std.Data.DTreeMap.Internal.Operations

-- Exporting this definition also exports its generated termination proof,
-- `Std.DTreeMap.Internal.Impl.link2._unary._proof_1`.
#check Std.DTreeMap.Internal.Impl.link2
```

The relevant Lean definition is in
`_deps/lean4-src/src/Std/Data/DTreeMap/Internal/Operations.lean`:

```lean
def link2 (l r : Impl α β) (hl : l.Balanced) (hr : r.Balanced) :
    Tree α β (l.size + r.size) :=
  match hl' : l with
  | leaf => ⟨r, ✓, ✓⟩
  | (inner szl k' v' l' r') =>
    match hr' : r with
    | leaf => ⟨l, ✓, ✓⟩
    | (inner szr k'' v'' l'' r'') =>
      if h₁ : delta * szl < szr then
        let ⟨ℓ, hℓ₁, hℓ₂⟩ := link2 l l'' ✓ ✓
        ⟨balanceLErase k'' v'' ℓ r'' ✓ ✓ ✓, ✓, ✓⟩
      else if h₂ : delta * szr < szl then
        let ⟨ℓ, hℓ₁, hℓ₂⟩ := link2 r' r ✓ ✓
        ⟨balanceRErase k' v' l' ℓ ✓ ✓ ✓, ✓, ✓⟩
      else
        ⟨glue l r ✓ ✓ ✓, ✓, ✓⟩
termination_by sizeOf l + sizeOf r
```

The termination elaborator produces the declaration
`Std.DTreeMap.Internal.Impl.link2._unary._proof_1`. Its proof uses Lean's
`Nat.Linear` normalization and an `eagerReduce`-wrapped reflexivity argument.

## Exact isolated Rocq reproduction

The current machine contains a precompiled prefix immediately before the
failing declaration:

```text
/tmp/prefixcurrentstock/Prefix91456.vo
/tmp/prefixcurrentstock/EagerCertificates.vo
/tmp/rocq-lean-import.pcAsPC/input.lean-export
```

The driver `/tmp/prefixcurrentstock/Link2Proof1.v` is:

```rocq
From LeanImport Require Import Lean.
Require Import Prefix91456.
Require Import EagerCertificates.

Set Kernel Conversion Dep Heuristic.
Set Lean Error Mode "Fail".
Set Lean Line Timeout 300.

Lean Import "/tmp/rocq-lean-import.pcAsPC/input.lean-export" 91456 91457.
```

Build the selected importer and run the isolated declaration with:

```sh
opam exec --switch=rocq93_clean -- \
  make -C _worktrees/rocq-lean-import/generic-cslib-current -f Makefile.rocq \
  src/lean_import.cmxs

/usr/bin/time -v timeout 300s \
  opam exec --switch=rocq93_clean -- rocq c \
    -I _worktrees/rocq-lean-import/generic-cslib-current/src \
    -Q _worktrees/rocq-lean-import/generic-cslib-current/src LeanImport \
    -Q /tmp/prefixcurrentstock '' \
    /tmp/prefixcurrentstock/Link2Proof1.v
```

The important progress lines are:

```text
line 91456: Std.DTreeMap.Internal.Impl.link2._unary._proof_1
line 91456: PSigma_inst3.(field).snd
line 91456: PSigma_inst3.(field).fst
```

The full cslib run on the clean integration branch reached the corresponding
entry at line 500013 of the full export and then made no further progress. A
measured run was stopped after 493 seconds at about 6.27 GB maximum RSS.

## What `eagerReduce` means in Lean

Lean declares:

```lean
@[expose] def eagerReduce {α : Sort u} (a : α) : α := a
```

As a term, it is just the identity. Its important behavior is not expressed by
that definition. It is hard-coded in the Lean kernel.

In `src/kernel/type_checker.cpp`, Lean recognizes an application argument whose
head is `eagerReduce`, then enables `m_eager_reduce` only while checking the
argument's inferred type against the function domain:

```cpp
if (is_eager_reduce(app_arg(e))) {
    flet<bool> scope(m_eager_reduce, true);
    if (!is_def_eq(a_type, d_type))
        throw app_type_mismatch_exception(...);
}
```

The flag affects at least these conversion paths:

```cpp
if ((!has_fvar(t_n) && !has_fvar(s_n)) || m_eager_reduce) {
    if (auto t_v = reduce_nat(t_n)) ...
}
```

and:

```cpp
if ((!has_fvar(t) || m_eager_reduce) && is_constant(s, Bool.true)) {
    if (is_constant(whnf(t), Bool.true))
        return true;
}
```

The second excerpt is particularly relevant. Without the marker, Lean's basic
reflection shortcut is normally restricted to a closed Boolean term. With the
marker, Lean may reduce a Boolean expression containing free variables when
the computation nevertheless normalizes to `true`.

Thus `eagerReduce` is a scoped instruction to Lean's conversion algorithm, not
a new logical reduction rule and not a theorem.

## The translation gap

`rocq-lean-import` translates the Lean constant and its application as ordinary
Rocq terms. Rocq therefore sees a transparent identity wrapper, but no syntax
whose presence asks its kernel to use Lean's special local strategy.

Schematically, Lean checks an application such as:

```lean
someLemma ... (eagerReduce (Eq.refl true))
```

The proof term has the easy inferred type:

```text
true = true
```

while the function expects a type of the form:

```text
largeOpenBooleanComputation = true
```

Lean's scoped eager conversion establishes that the left-hand Boolean reduces
to `true`. Rocq must establish the analogous conversion after translation, but
ordinary Rocq conversion explores the large term poorly and stalls.

This distinction matters:

- the terms appear to be definitionally equal;
- the imported declaration is not known to be ill-typed;
- the importer is not missing a cslib-specific lemma;
- the practical failure is conversion strategy, sharing, and term
  representation at the target kernel boundary.

## What has been established experimentally

### 1. The computation itself is tractable

An importer-side, demand-driven evaluator reduces the target Boolean to
`true` in roughly three seconds. This evaluator does not by itself constitute
a valid solution, because its answer is OCaml data and must not be trusted.

One trace before adding reusable reduction equations contained 513
transitions:

```text
488 definitional transitions
25 reflected Nat/Bool transitions
```

The code constructed a local proof object for each transition in about 9.27
seconds. This demonstrates that no individual computational step is
intrinsically difficult.

A later trace, after recognizing more steps through small generic equations,
contained 556 transitions:

```text
197 equation-backed transitions
334 remaining definitional transitions
25 reflected Nat/Bool transitions
```

Most of the remaining definitional transitions are ordinary constant
unfolding, beta/zeta/iota reduction, projection reduction, or one fixpoint
unfolding.

### 2. A flat certificate loses crucial sharing

Constructing all local equalities is much easier than asking Rocq to check
their fully composed proof. The composed term repeats large intermediate
states in its types and contexts.

At one representative transition, the left endpoint had:

```text
329 physically unique nodes
17687 nodes when traversed as a tree
90 repeated subgraphs
```

The right endpoint had:

```text
311 physically unique nodes
14068 tree nodes
87 repeated subgraphs
```

Other generated checkpoint proofs reached tree sizes in the hundreds of
thousands despite having only hundreds of unique nodes. Therefore the relevant
cost is not just the number of reduction steps; it is loss of DAG sharing when
large endpoints are embedded repeatedly into equality types and transports.

### 3. Opaque checkpointing is not sufficient by itself

Declaring intermediate equalities as opaque lemmas bounds live memory, but it
also repeats large endpoints in successive lemma statements. Runs then become
progressively slower. For example, a checkpoint after transition 42 took about
34.5 seconds to infer a single opaque proof, with more than 500 transitions
still pending.

Changing checkpoint sizes moves the bottleneck rather than removing it.

### 4. The context is dependent

Many reduction paths pass through projection scrutinees, for example:

```text
arg0/projection-scrutinee/arg2/...
```

For a dependent record, replacing the record value can change the type of a
later projection. Consequently, a generic one-hole context cannot always be
represented by a homogeneous function `C : A -> B`, and `f_equal C` is not a
valid lifting rule for every frame.

Experimental code introduced type equality, heterogeneous equality, explicit
transport, and proof-irrelevant bridges. This made more individual steps
constructible, but it did not yield a compact final certificate accepted by
stock Rocq. This is an essential design issue, not just a missing case in a
simple AST zipper.

## Approaches tried and why none is yet a solution

| Approach | Observation | Why it is insufficient |
|---|---|---|
| Ordinary stock Rocq conversion | Stalls on the isolated declaration and consumes several GB | Does not reproduce Lean's local eager strategy efficiently |
| Existing closed arithmetic certificates | Successfully solve earlier closed `Nat` computations | The present Boolean computation is open and structurally much larger |
| Importer evaluator without proofs | Reduces the Boolean to `true` in a few seconds | Would extend trust to the importer if its result were accepted directly |
| Flat chain of checked equality steps | Every local step can be constructed | Full composition repeats huge endpoints and becomes impractical to check |
| Opaque chunks/checkpoints | Bounds parts of live memory | Repeats large endpoint types and becomes progressively slow |
| Let-abstraction / physical DAG experiments | Greatly shrinks some in-memory/tree counts | Did not provide stable sharing through declaration serialization and kernel checking |
| Whole-term VM cast | Did not complete within practical memory/time | Large open/dependent term remains too expensive |
| Native cast | Native compiler is disabled in this Rocq build and falls back to VM | Not a working stock-Rocq path; portability and replay would still need analysis |
| Modified Rocq conversion heuristics | Several lazy/flex-rigid experiments changed profiles | No experiment produced a validated, general, replayable solution |
| Hierarchical/zipper certificate | Avoids lifting every tiny step through the full outer context | Dependent projections require heterogeneous transport; naïve closure or checkpoint schemes still flatten/repeat large terms |

No row in this table should be described as a completed fix.

## Current experimental branch: warning

The worktree

```text
_worktrees/rocq-lean-import/eager-proof-current
branch: fix/eager-reduce-proof-producing
```

is an experimental notebook in code form, not a candidate PR. Its current
status includes unresolved files:

```text
UU src/Lean.v
UU src/lean.ml
?? .lia.cache
```

and the diff is roughly ten thousand added lines. It contains useful probes,
statistics, and failed certificate designs, but it should not constrain a new
design and must not be reviewed as if it were a nearly finished
implementation.

The two WIP commits are:

```text
ddca669 WIP prototype proof-producing eagerReduce certificates
6a2a7b9 WIP bound proof-producing evaluator checkpoints
```

## Design problem to solve

A satisfactory design must answer all of the following.

### Semantics

1. What exact judgment does Lean establish under `m_eager_reduce` in this
   application, and which parts go beyond ordinary weak-head conversion?
2. Is the gap purely algorithmic, or does faithfully importing the marker
   require recording additional evidence in the target term?
3. Should `eagerReduce` remain a recognizable marker in the translated term,
   or should the importer replace each occurrence with an explicit proof?

### Architecture

4. Which layer is the right one?
   - importer term translation;
   - a reusable Rocq proof-producing normalizer;
   - a persistent Rocq conversion strategy/oracle;
   - or a small general Rocq-kernel feature analogous to Lean's scoped marker?
5. If importer-side certificates are preferred, how should closures,
   environments, contexts, and reduction results be represented so the output
   remains a DAG rather than a flattened tree?
6. Can equation lemmas be applied to compact closures without reifying every
   full intermediate endpoint in their types?
7. How is sharing preserved in the final kernel term and `.vo`, rather than
   only in OCaml memory before declaration?

### Dependent terms

8. What is the principled congruence rule for an evaluation context containing
   dependent applications, cases, and primitive projections?
9. Is a typed dependent zipper, heterogeneous equality, equality of sigma
   packages, or a logical relation the simplest correct representation?
10. Can proof irrelevance or `SProp` eliminate some transports without relying
    on a large conversion to prove that the differing fields are irrelevant?

### Trust and replay

11. Which facts are checked by the Rocq kernel, and which computations remain
    in the trusted base?
12. If a kernel/conversion-oracle solution is proposed, how is the local
    strategy recorded so checking a `.vo` cannot depend on transient plugin
    state?
13. What prevents a buggy importer evaluator from creating a false theorem?

### Practicality

14. What asymptotic and concrete term-size bound should replace the current
    repeated endpoint chain?
15. What is the smallest implementation surface likely to be acceptable
    upstream?
16. Which solution generalizes from this proof to other uses of
    `eagerReduce`, `decide`, `omega`, open terms, universes, and dependent
    records?

## Acceptance criteria

A proposed design should be considered credible only if its eventual
implementation can satisfy this sequence:

1. The minimal `dtree-link2-hconstr-timeout.lean` export succeeds with a
   practical time and memory bound.
2. The exact isolated import range `91456 91457` succeeds from the precompiled
   prefix.
3. The imported declaration is accepted by the stock Rocq kernel, not only by
   a plugin-side precheck.
4. A fresh Rocq process can load the resulting `.vo` without reconstructing
   transient evaluator state.
5. Deliberately corrupting a certificate causes Rocq to reject it.
6. Existing Lean Kernel Arena positive and negative tests retain their verdicts.
7. The full cslib frontier advances beyond `link2._unary._proof_1` and the loop
   continues to the next genuine incompatibility.
8. The patch contains no cslib-specific name, proof, or rewrite.
9. Measurements include wall time, peak RSS, generated term/`.vo` size, and a
   comparison against the clean integration branch.

## Most promising high-level direction observed so far

This is a hypothesis, not a conclusion: a generic proof-producing evaluator
probably needs to keep closures as code plus environment and emit small,
Rocq-checked equation applications as a DAG. It should avoid materializing the
entire source and target term at every transition. The dependent-context story
must be designed first-class rather than added after a homogeneous zipper.

The next analysis should compare that architecture honestly with a small
kernel feature that gives Rocq a scoped eager-conversion mode. In particular,
it should determine whether a kernel feature can remain purely algorithmic and
replayable, or whether it would merely hide the same sharing problem.

## Evidence and source map

Core files:

```text
README.md
config/rocq-lean-import.lock.json
rocq-lean-import-pr-stack.md
docs/denote-toNormPoly-diagnostic.md
docs/nat-linear-minimal-repro.md
_deps/lean-kernel-arena/tests/repros/dtree-link2-hconstr-timeout.lean
_deps/lean4-src/src/Init/Core.lean
_deps/lean4-src/src/kernel/type_checker.cpp
_deps/lean4-src/src/Std/Data/DTreeMap/Internal/Operations.lean
_worktrees/rocq-lean-import/generic-cslib-current/src/Lean.v
_worktrees/rocq-lean-import/generic-cslib-current/src/lean.ml
```

Current-machine isolated artifacts:

```text
/tmp/prefixcurrentstock/Link2Proof1.v
/tmp/prefixcurrentstock/Prefix91456.vo
/tmp/prefixcurrentstock/EagerCertificates.vo
/tmp/prefixcurrentstock/build.log
/tmp/link2-single-redex.log
/tmp/link2-diag-graph-59.log
/tmp/link2-def-stats.log
/tmp/link2-hierarchical-hybrid-summary.log
/tmp/link2-safechunks64.log
/tmp/link2-whole-native.log
```

The `/tmp` files are diagnostic artifacts and may disappear after reboot. The
source reproduction and repository scripts are the durable entry points.

## Addendum: diagnostic gates for the proposed `EAGERcast`

The gates requested by the external design review were run against the exact
declaration at export line 91456.  They do **not** currently justify adding an
`EAGERcast`.

### Gate A — exact obligation

The first expensive comparison is closed in a relative context of size 22.
Its inferred side reduces to `Bool_true = Bool_true`; its expected side is the
corresponding `Nat.Linear` normalization result.  The pair digest is:

```text
bb0d5902e34d48c9746fe9b8ea55ca08c1e2385abe689f27a4796c806d74e2fd
```

### Gate B — unique immediate blocker

A disposable kernel bypass restricted to that exact digest lets the complete
declaration pass in 1.22 seconds (451348 KiB peak RSS).  The comparison is
therefore the sole immediate blocker for this declaration.

### Gate C — causal role of Lean's marker

Lean 4.29 was asked to check a new copy of the exact theorem body, once with
its sole `eagerReduce` application intact and once after removing it.  Both
copies were accepted synchronously:

```text
marker retained: 4.18 s, 1396176 KiB
marker removed:  4.06 s, 1398404 KiB
```

For this stored declaration, the marker is therefore neither necessary for
typing nor measurably necessary for performance.  A marker-specific target
cast would preserve a correlation, not a demonstrated source-kernel need.

### Gate D — target definitionality

The 556 evaluator transitions comprise 334 ordinary definitional steps, 197
equation-guided steps, and 25 reflected Boolean/Nat steps.  Each of the 25
reflected local endpoints was independently accepted by ordinary Rocq
conversion.  A whole-endpoint VM conversion did not finish in 300 seconds and
reached 5299072 KiB, so a practical whole-graph target converter has not yet
established the final pair.

### Gate E — actual reduction cost

The stock converter spends its time inside one head-reduction request.  At
100 million reduction steps it had performed no full term readback and only
three top-level conversion calls.  The initial apparent process repetitions
were then checked with a versioned key consisting of closure identity, the
exact immutable `fterm` snapshot, and stack identity:

```text
completed head-cache hits: 0
active-state reentries:    0
```

Thus the observed repeated closure pointer was advancing through distinct
mutable states; it was not the same semantic state being recomputed.  A naive
cache that ignored those versions was also shown unsound by a failure while
building `Corelib.Init.Datatypes`.

The expensive translated computation contains closed Lean naturals such as
`Nat.Linear.fixedVar = 100000000`.  Lean compares these using its compact
kernel Nat reducer.  The target represents them as an ordinary inductive
`Nat` (with a lazy binary decoder), so operations such as equality still
eventually traverse a very large unary spine.  This is currently stronger
evidence for a missing target-side compact-Nat reduction facility than for a
generic loss of graph sharing.

### Existing alternatives

Neither existing persistent cast strategy solves the exact pair:

```text
VMcast:     timeout after 300 s, 5299072 KiB
NATIVEcast: stack overflow (also with a 256 MiB process stack)
```

Assigning every imported definition Rocq's `Expand` strategy also timed out
after 120 seconds, so this is not merely a constant-unfolding-order issue.

### Decision

Do not upstream the current proof-producing prototype, the naive `CClosure`
cache, or a marker-only `EAGERcast`.  The next implementation experiment
should be a small, generic, kernel-checked compact reduction facility for
closed unary-Nat operations (or an equivalent correction to the target Nat
translation).  It must first solve the exact pair and then pass the ordinary
Rocq kernel suite before any persistent cast syntax is added.
