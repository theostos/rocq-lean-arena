# `rocq-lean-import` review-ready PR stack

This is the current handoff for the branches in
[`theostos/rocq-lean-import`](https://github.com/theostos/rocq-lean-import).
The work is based on `rocq-community/rocq-lean-import` at `38fb479`, except
for the UInt32 train, which starts from upstream `fix-UInt32` at `fc148df`.

The stack contains importer fixes and generic, Rocq-checked translation
mechanisms only. It does not contain declaration-specific cslib proofs,
admitted terms, native casts, or theorem-opacity shortcuts.

## Current result

- Every proposed branch was inspected and rebuilt on Rocq 9.3.
- The final integration head, `pr/compact-nat` at `48ba271`, passes the full
  repository suite in 42.85 seconds with 1,597,332 KiB peak RSS.
- The former `Char.ofNat`-specific implementation was removed. Its branch now
  implements generic certified transport for imported proof arguments.
- The comparison branch now actually applies its Boolean certificates during
  import. The original branch only declared certificate lemmas.
- Generated primitive-record eliminators and eta expansions are now checked
  for conversion against the original term, not merely assigned a similar
  type.
- The mutual-nested implementation was rewritten to remove its separate Array
  path, remove speculative registration of 32 auxiliary recursors, and share
  one structural path across Array, List, Option, Prod, mutual blocks, and
  eligible records. Rocq 9.3 `AllForall` evidence is now reused recursively
  instead of maintaining a second direct-recursion engine.
- A final clarity pass replaced opaque mutual/layout tuples with named state,
  merged the repeated unary-container paths, shared closed-term reduction
  between arithmetic and comparisons, and extracted primitive projection
  alias construction. Focused regressions and the full suite were rerun after
  the refactor.

## Branch-by-branch audit

| Branch | Review result |
|---|---|
| `pr/hex-parser` | Kept the small parser fix; added structured malformed-input handling and boundary regressions. |
| `pr/name-escaping` | Kept the generic escape table; added a collision regression for already-escaped source names. |
| `pr/universe-instances` | Kept the unified representation; added an exact imported-type assertion. |
| `pr/projection-relevance` | Replaced repeated dependent-field rebuilding with one linear telescope walk and exact checks. |
| `pr/mutual-inductives` | Centralized scheme declaration and recursor registration; named translated packets and pending-block state replace shadowed functions and tuple plumbing. |
| `pr/nested-containers` | Retained the structural adapter after testing Rocq 9.3 limits; its argument parsing and two-stage adaptation are now explicit and documented. |
| `pr/mutual-nested-recursor` | Reduced to one final-design commit: one structural path, actual `rec_N` parsing, no fixed auxiliary-name limit, and recursive reuse of Rocq 9.3 `AllForall` evidence. Generated export dumps are collapsed in GitHub reviews. |
| `pr/nested-record-containers` | Replaced Boolean folding state with explicit `RawLeaves`/`FoldedLeaves` states. |
| `pr/sprop-scheme-relevance` | Relevance now comes from instantiated types; SProp regressions check exact sorts. |
| `pr/uint32-version-aware` | Tightened modern layout assertions while preserving the legacy fixture. |
| `pr/string-of-list` | Small shape-based compatibility patch retained and rebuilt unchanged. |
| `feature/proof-producing-arithmetic` | Rebased onto the reviewed importer pipeline; factored one transparent closed-reduction step shared by all certificate reifiers. |
| `pr/char-of-nat` | Old private-name implementations deleted; branch replaced by generic certified application-argument transport. |
| `feature/primitive-record-eliminators` | Added a kernel conversion check and extracted projection-alias discovery from inductive declaration. |
| `feature/eta-long-record-definitions` | Added a kernel conversion check for every eta-long replacement. |
| `feature/proof-producing-nat-sub` | Kept the compositional subtraction rule and removed stale Char-specific dependencies. |
| `feature/proof-producing-nat-comparisons` | Fixed the main omission and now reuses arithmetic’s closed-reduction helper instead of duplicating it. |
| `pr/nat-deceq` | Kept the checked core predeclaration; verified both Decidable branches and removed unrelated dependencies. |
| `pr/compact-nat` | Replaced all-or-nothing compact decoding with an adaptive small/eager/compact policy after a Char stack-overflow regression. |

Full cached cslib does not compile yet. After the clarity pass, the final head
was rerun with the importer stopped immediately before export line 500,013;
that frontier check passes. The integrated importer also passes the earlier
nested-array, nested-Prod, and mutual-recursion reproductions. A complete run
then reaches the next item,
`Std.DTreeMap.Internal.Impl.link2._unary._proof_1`. That item remains a generic
proof-term evaluation and sharing problem: the process reached roughly 6 GiB
before being stopped. This must not be described as full cslib support.

## Rocq 9.3 nested-scheme assessment

Rocq 9.3 materially improves nested eliminators through registered
`All`/`AllForall` schemes, and the stack uses that machinery for ordinary
containers such as List and Option.

It does not make the importer’s remaining adapters redundant:

- `Scheme All` explicitly does not support primitive records, which includes
  the relevant Array/Prod/record encodings used by the importer.
- A tested attempt to generate partial native schemes lazily for
  `PersistentHashMap.Entry` changed Rocq’s missing-scheme warning into an
  illegal universe application through Array. The generated predicate lived
  in `Type@{max motive parameter}`, while Array’s nested predicate had to stay
  in the recursor motive universe.
- Lean and Rocq also order recursive hypotheses differently, and Lean exports
  auxiliary `rec_N` declarations that still need structural alignment.

The retained implementation therefore delegates to Rocq 9.3 where its API is
sound for the exported shape, and uses checked structural/projection adapters
for the cases Rocq does not cover.

## Submission order

These PRs can start independently:

1. `pr/hex-parser`
2. `pr/name-escaping`
3. `pr/universe-instances`
4. `pr/uint32-version-aware` against upstream `fix-UInt32`

Then submit the two dependent trains in order.

### Translation train

| Order | Branch | Current head |
|---:|---|---|
| 1 | `pr/universe-instances` | `acc57bd` |
| 2 | `pr/projection-relevance` | `18440ee` |
| 3 | `pr/mutual-inductives` | `a086ac3` |
| 4 | `pr/nested-containers` | `9c6fea8` |
| 5 | `pr/mutual-nested-recursor` | `7dc75d0` |
| 6 | `pr/nested-record-containers` | `66d38b7` |
| 7 | `pr/sprop-scheme-relevance` | `a528b89` |

### Lean-core compatibility train

| Order | Branch | Current head |
|---:|---|---|
| 1 | `pr/uint32-version-aware` | `4846a81` |
| 2 | `pr/string-of-list` | `3aa1dc3` |

`pr/uint32-base` mirrors upstream `fix-UInt32`; do not open it as a PR.

### Arithmetic and scalability train

This train currently sits on `integration/cslib-import-stack`, which combines the
accepted bases above. Do not propose the integration branch itself.

| Order | Branch | Current head |
|---:|---|---|
| 1 | `feature/proof-producing-arithmetic` | `b53e59c` |
| 2 | `pr/char-of-nat` | `1f8dd90` |
| 3 | `feature/primitive-record-eliminators` | `ef61de6` |
| 4 | `feature/eta-long-record-definitions` | `374d595` |
| 5 | `feature/proof-producing-nat-sub` | `0b05bde` |
| 6 | `feature/proof-producing-nat-comparisons` | `d3bb9f8` |
| 7 | `pr/nat-deceq` | `b43b35f` |
| 8 | `pr/compact-nat` | `48ba271` |

After predecessor PRs merge, rebase each next branch onto the merged upstream
head and push with `--force-with-lease`. This keeps each GitHub diff focused
on its own commits.

---

# Copy-ready GitHub PR bodies

Each section below includes a suggested title followed by a compact PR body.

## `pr/hex-parser`

**Title:** Fix hexadecimal byte parsing

### Summary

Decode hexadecimal export fields correctly in both lowercase and uppercase,
and report malformed input as an importer error instead of asserting.

### Before and after

Before, `6a` was rejected and `6A` decoded `A` with the wrong `0..5` offset.
After, both spellings decode to the same byte, and an invalid digit produces a
localized error.

### Why it matters

Hexadecimal bytes are part of the export format, so this affects every Lean
library rather than any particular declaration.

### Tests

Adds lowercase, uppercase, invalid-digit, and invalid-width fixtures. The full
integration suite passes on Rocq 9.3.

## `pr/name-escaping`

**Title:** Escape punctuation in imported Lean names

### Summary

Extend Lean-to-Rocq name conversion with deterministic, collision-safe escapes
for punctuation that is legal in Lean but not in Rocq identifiers.

### Before and after

Before, a declaration named `foo-bar` could produce an invalid Rocq name.
After, it imports as `foo__dashbar`; a source name already using that spelling
is kept distinct.

### Why it matters

The rule applies uniformly to all imported names and prevents both syntax
errors and accidental collisions in large libraries.

### Tests

Adds punctuation and escaped-name collision regressions. The full integration
suite passes on Rocq 9.3.

## `pr/universe-instances`

**Title:** Represent imported universe instances uniformly

### Summary

Represent every translated universe instance as a complete list of
expressions over the Lean universe parameters. Add a kernel type assertion to
the regression so parameter shifts cannot pass unnoticed.

### Before and after

Before, separating original parameters from algebraic `max`/`succ`
expressions could duplicate or shift an instance. After, an application such
as `UniverseBox.{0, 1} Nat` receives exactly the instance exported by Lean.

### Why it matters

The same representation is used for definitions, inductives, eliminators,
quotients, and cumulative `ULift`; it is not declaration-specific.

### Tests

Exercises successor/maximum universes and checks the exact imported result
type. The branch suite passes on Rocq 9.3.

## `pr/projection-relevance`

**Title:** Translate dependent fake projections soundly

### Summary

Build non-primitive projections in one telescope pass, substituting each
earlier projection into later field types and deriving case relevance from
the instantiated field type.

### Before and after

For

```lean
structure DepRec where
  proposition : Prop
  proof : proposition
  next : DepRec
```

the old translation could give `proof` the wrong dependency or relevance.
The new translation checks `r.proof : r.proposition` exactly.

### Why it matters

This follows dependent record typing generically and also avoids repeatedly
rebuilding the preceding telescope.

### Tests

Adds exact checks for all dependent projections. The branch suite passes on
Rocq 9.3.

## `pr/mutual-inductives`

**Title:** Import mutual Lean inductive blocks

### Summary

Detect consecutive entries from one Lean mutual block, declare them together
in Rocq, and share recursor declaration and registration across every member.

### Before and after

Before, mutually recursive `Tree` and `Forest` entries were declared
separately, leaving invalid recursive references. After, both recursors have
the expected mutual motives and a closed fold reduces to `2`.

### Why it matters

Grouping and reference remapping are derived from the exported block
structure, not from type names.

### Tests

Checks the exact types of both recursors and evaluates the mutual fold. The
branch suite passes on Rocq 9.3.

## `pr/nested-containers`

**Title:** Adapt Lean recursors through nested containers

### Summary

Use Rocq 9.3 registered nested schemes where available and structurally adapt
recursive hypotheses through Array, its List representation, and the
recursive component of Prod.

### Before and after

Before, a rose tree constructor with `children : Array (Rose α)` produced a
Rocq eliminator that did not match Lean’s nested recursor. After, the main and
auxiliary size functions import and reduce to `2`; the Prod example reduces
to `3`.

### Why it matters

Selection is based on registered container structure. No cslib theorem or
namespace is recognized specially.

### Tests

Includes Array, List-auxiliary, and Prod regressions with computation checks.
The branch suite passes on Rocq 9.3.

## `pr/mutual-nested-recursor`

**Title:** Unify adaptation of mutual nested recursors

### Summary

Generalize nested-recursion adaptation to mutual blocks and auxiliary
`rec_N` declarations. The implementation now has one structural path for
Array, List, Option, Prod, mutual inductives, and supported records.

This rewrite removes the former Array-specific path, derives the real mutual
block from the recursor type, and replaces speculative registration of 32
auxiliary names with registration of only declarations present in the export.
It also reuses Rocq 9.3 `AllForall` evidence recursively instead of carrying a
second hand-written recursion engine. The branch is one final-design commit;
generated export dumps are marked as generated for GitHub review.

### Before and after

Before, a `NestedTree`/`NestedForest` block below List could not align its
auxiliary motives and recursors. After, both main recursors and `rec_1` import,
and the closed example reduces to `4`; the Option example reduces to `3`.

### Why it matters

The adapter is driven by mutual-block, motive, and container metadata. It does
not reprove or replace any imported theorem.

### Tests

Checks main and auxiliary recursors for Option and mutual List nesting. The
branch and final integration suites pass on Rocq 9.3.

## `pr/nested-record-containers`

**Title:** Support nested recursion through record containers

### Summary

Derive projection-based nested schemes for eligible primitive records and
make the folding state explicit as `RawLeaves` or `FoldedLeaves`.

### Before and after

Before, recursion stopped when a recursive value was wrapped in a record such
as `Payload RecordTree`. After, `List (Payload RecordTree)` imports through
the same structural adapter and the example reduces to `10`.

### Why it matters

Record eligibility comes from its parameters and projections, not from the
record’s name.

### Tests

Exercises the main record recursor plus List and Payload auxiliary recursors.
The branch suite passes on Rocq 9.3.

## `pr/sprop-scheme-relevance`

**Title:** Derive relevance in generated nested schemes

### Summary

Compute binder, projection, and case relevance from instantiated types instead
of hard-coding relevance in generated nested schemes.

### Before and after

Before, instantiating a generated record scheme at `SProp` could retain
Type-like relevance. After, the same generic code imports both
`Box True : Type` and `Nonempty True : SProp` with their exact sorts.

### Why it matters

Relevance is derived from Rocq’s type information for every generated scheme,
including future SProp-valued inputs.

### Tests

Checks exact `Box` and `Nonempty` SProp instantiations. The translation train
and final integration suite pass on Rocq 9.3.

## `pr/uint32-version-aware`

**Title:** Support legacy and current UInt32 layouts

### Summary

Inspect the exported kernel shape and select the matching UInt32 and Char
predeclarations. Keep the legacy Fin-backed representation and support the
current BitVec-backed representation.

### Before and after

Before, choosing one representation unconditionally broke exports from the
other Lean generation. After, current-Lean definitions
`modernUInt32Identity` and `modernCharIdentity` import while the legacy fixture
continues to pass.

### Why it matters

Dispatch follows the core type shape and is independent of downstream
libraries.

### Tests

Checks exact modern UInt32, BitVec, and Char shapes plus the legacy tests. The
branch suite passes on Rocq 9.3.

## `pr/string-of-list`

**Title:** Support modern `String.ofList` construction

### Summary

Support both core string encodings by selecting the constructor present in the
export and inferring its character and list types.

### Before and after

Before, modern literals built with `String.ofList` were not recognized.
After, `def stringFromLiteral : String := "ok"` imports as a Rocq `String`,
while older `String.mk` exports remain supported.

### Why it matters

This is version-compatible Lean core handling, not a library-specific rewrite.

### Tests

Adds a current-Lean string literal fixture. The compatibility and integration
suites pass on Rocq 9.3.

## `feature/proof-producing-arithmetic`

**Title:** Certify closed Nat conversion with Rocq-checked proofs

### Summary

Reflect supported closed Nat expressions to binary `N`, construct a generic
`NatCertificate`, and transport across the equality checked by Rocq’s kernel.

### Before and after

Before, checking that `2^64` equals `18446744073709551616` could expand huge
unary naturals and consume gigabytes. After, an imported proof can transport
between those forms using a small binary certificate.

### Why it matters

Certificates compose over arithmetic syntax. The importer computes the
candidate value, but Rocq checks the equality; there is no theorem-name match,
admission, or native cast.

### Tests

Includes large literal, power, addition, multiplication, and transport
regressions. The final integration suite passes on Rocq 9.3.

## `pr/char-of-nat`

**Title:** Transport proof arguments across certified Nat equalities

### Summary

Apply certified Nat transport generically to application arguments and
normalize both ordinary and hexadecimal numeral encodings.

This replaces the previous branch completely: it no longer predeclares or
matches private `Char.ofNat` proof names.

### Before and after

Before, a proof argument mentioning the literal `65` could fail to match the
equivalent certified Nat expression expected by `Char.ofNat`. After, the
generic application translator transports that argument across the checked
equality, and `Char.ofNat 65` imports normally.

### Why it matters

The rule applies to any imported application whose proof arguments differ
only by a certified closed Nat equality.

### Tests

Keeps a real Lean 4.26 `Char.ofNat` export as a regression and exercises the
generic transport path. The final integration suite passes on Rocq 9.3.

## `feature/primitive-record-eliminators`

**Title:** Use primitive projections for record eliminators

### Summary

Translate eligible one-branch primitive-record eliminators into projection
applications so a neutral record value is not forced merely to expose its
fields. Kernel conversion now verifies the replacement against the original
generated eliminator.

### Before and after

Before, projecting a pair returned by a ten-million-step computation timed out
because the generic match forced the pair body. After, `.fst` and `.snd` stay
lazy and the regression completes in under a second.

### Why it matters

The optimization is selected solely from Rocq primitive-record metadata and
is guarded by a conversion check.

### Tests

Includes the expensive neutral-record reproduction and semantic conversion
verification. The final integration suite passes on Rocq 9.3.

## `feature/eta-long-record-definitions`

**Title:** Eta-expand primitive-record-valued definitions

### Summary

Store primitive-record-valued imported definitions in eta-long constructor
form, and verify by kernel conversion that the expansion has the original
meaning.

### Before and after

Before, checking record eta for an expensive pair could unfold its
ten-million-step source computation. After, the constructor and projections
are visible immediately, so `p = (p.1, p.2)` checks quickly.

### Why it matters

Expansion is determined only by the translated result’s primitive-record
shape and is protected by Rocq conversion.

### Tests

Adds an expensive record-valued definition and eta regression. The final
integration suite passes on Rocq 9.3.

## `feature/proof-producing-nat-sub`

**Title:** Add checked certificates for closed Nat subtraction

### Summary

Extend Nat certificate composition with binary computation and a Rocq proof
for `Nat.sub`, including truncation at zero.

### Before and after

Before, `100000000 - 99999999` could require linear unary reduction. After,
Rocq checks a compact certificate for the result `1`; `3 - 10 = 0` exercises
the truncated branch.

### Why it matters

The rule applies to every supported closed subtraction expression and reuses
the generic certificate boundary.

### Tests

Checks both large and truncated subtraction certificates. The final
integration suite passes on Rocq 9.3.

## `feature/proof-producing-nat-comparisons`

**Title:** Use checked certificates for imported Nat comparisons

### Summary

Add Boolean certificates for `Nat.beq`, `Nat.ble`, and `Nat.blt`, reify those
expressions during import, and transport proof arguments across the certified
Boolean equality.

### Before and after

Before, the branch declared comparison lemmas but never used them; importing
`99999999 < 100000000` still took about 15.7 seconds. After, the real Lean
fixture imports through checked reflection in about 0.4 seconds.

```lean
def castComparison
    (h : Nat.blt 99999999 100000000 = true) :
    Nat.ble 100000000 100000000 = true := h
```

### Why it matters

Recognition is by operation shape, and Rocq checks every Boolean result.

### Tests

Adds a real imported comparison/transport fixture plus true and false
certificate cases. The final integration suite passes on Rocq 9.3.

## `pr/nat-deceq`

**Title:** Predeclare Lean Nat decidable equality

### Summary

Provide the core `False`, `Decidable`, and `Nat.decEq` declarations using the
already checked Boolean Nat equality path.

### Before and after

Before, every modern export could import the large generic recursive
implementation of `Nat.decEq`. After, both `Nat.decEq 1 1` and
`Nat.decEq 0 1` reduce through the compact registered core definition.

### Why it matters

This is one semantics-preserving Lean core predeclaration used by all
libraries; it does not replace downstream theorems.

### Tests

Checks both true and false Decidable constructor paths. The final integration
suite passes on Rocq 9.3.

## `pr/compact-nat`

**Title:** Decode imported Nat literals adaptively

### Summary

Decode large binary literals incrementally with `CompactPos`/`CompactNat`,
while retaining the eager decoder for medium values and direct unary
construction for small values. Both paths have distinct Rocq-checked
certificate lemmas.

### Before and after

Before, constructing a large literal through `N.to_nat` could allocate its
full unary intermediate; using CompactNat for every value also made ordinary
Char bounds overflow the conversion stack. After, decoding is adaptive:
small and medium terms stay shallow, while 32-bit-scale literals use the
incremental representation.

### Why it matters

The policy depends only on literal size and preserves the checked certificate
API for every consumer.

### Tests

Checks compact exposure and certificates, the full Char fixture, large
comparison transport, and the complete repository suite. Final result:
42.85 seconds and 1,597,332 KiB peak RSS on Rocq 9.3.

## Remaining cslib work

The next work should not be another named proof replacement. The outstanding
`Std.DTreeMap.Internal.Impl.link2._unary._proof_1` case needs a generic,
sharing-preserving proof-producing evaluator: closures should remain as an
environment, and small opaque Rocq-checked equation applications should form
a DAG. The existing eager-reduction prototype documents experiments in that
direction, but it is not ready for an upstream PR.
