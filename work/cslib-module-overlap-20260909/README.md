# CSLib: duplication from one export per Lean source file

Measured on 2026-09-09 against CSLib revision
`02e2a23eef42925cc87a5ce2ec76e9d07fdee267`, using its existing Lean
`4.27.0-rc1` compiled files and the original `cslib.ndjson` certificate.
This measures exported declarations and expression data. It is not a Rocq
checking-time benchmark.

## Result

There are **78 files under `Cslib/`**, of which **76 contain declarations
present in the certificate**. `Cslib.Init` and `Cslib.Foundations.Lint.Basic`
have no such declarations and generate no checking group. The top-level
`Cslib.lean` aggregation file is also omitted. These files contribute
**5,412 importer entries**, or 5,891 named Lean constants when constructors
and recursors are counted separately.

| Per-file export method | Groups | Unique entries across all groups | Sum of entries in separate exports | Repetition factor |
|---|---:|---:|---:|---:|
| Select declarations defined in each file, plus their dependencies | 76 | 26,088 | 173,286 | **6.64×** |
| Export each file's whole imported environment | 76 | 253,649 | 13,965,462 | **55.06×** |

The first method has **147,198 duplicate entry occurrences**: **84.95%** of
all entry occurrences in those separate exports repeat something included
in another group. The second has 13,711,813 duplicates, or 98.18%.

Expression data also overlaps heavily:

| Per-file export method | Unique expression nodes | Sum across separate exports | Repetition factor |
|---|---:|---:|---:|
| File-owned declarations plus dependencies | 2,974,372 | 14,231,792 | **4.78×** |
| Whole imported environment | 21,039,124 | 1,090,567,929 | **51.84×** |

These are shared expression DAG nodes, not expanded tree sizes or certificate
line counts. Each node is counted at most once within a group.

## Where the duplication occurs

For the file-owned method, CSLib's own 5,412 entries occur 11,814 times across
groups. The 20,676 entries from other libraries occur 161,472 times. Therefore
140,796 of the 147,198 duplicate occurrences (**95.65%**) come from external
dependencies.

The median dependency-trimmed file export contains **1,326 entries**; the
smallest contains 35 and the largest 17,119. Examples:

| Source module | Own entries | Entries including dependencies | Expression nodes |
|---|---:|---:|---:|
| `Cslib.Foundations.Data.HasFresh` | 51 | 17,119 | 1,569,819 |
| `Cslib.Computability.Languages.OmegaRegularLanguage` | 44 | 9,979 | 1,015,238 |
| `Cslib.Computability.Automata.NA.Loop` | 208 | 7,327 | 754,227 |
| `Cslib.Computability.Automata.Acceptors.Acceptor` | 12 | 35 | 949 |

Only seven entries are common to all 76 groups. Sharing should follow the
actual dependency graph; the useful shared dependencies differ between groups.

## A smaller combined export

Combining the selected roots from every CSLib file, then including their
dependencies once, gives **26,088 entries and 2,974,372 expression nodes**.
The current full-environment export contains 253,649 entries and 21,039,124
expression nodes. The combined selected export therefore has **89.71% fewer
entries and 85.86% fewer expression nodes**.

It covers every CSLib declaration present in the original certificate,
including exported private/generated helpers, and their transitive
dependencies. It does not attempt to check every other declaration in the
imported Lean/Std/Batteries/Mathlib environment. The original export enumerates
that entire environment, including declarations not needed by CSLib's roots.

To retain exactly the original full-export coverage with the file-owned
groups, an additional group can cover the remaining roots and their
dependencies. It contains 248,125 entries. The resulting 77 exports total
421,411 entries (1.66× the original unique set) and 34,190,800 expression nodes
(1.63×). This large remainder would itself remain a sequential job.

## Method and checks

1. `Metadata.lean` loads the existing `Cslib` environment and records each
   constant's defining module using `Environment.getModuleIdxFor?`. It does
   not infer file ownership from namespaces. It traverses types, definition
   and proof bodies, opaque bodies, recursor rules, mutual inductive families,
   quotient primitives, and implicit dependencies of Nat/string literals.
2. `Modules.lean` reads direct module imports from compiled module headers.
3. `analyze.py` scans the actual NDJSON certificate and matches its constants
   to that metadata. It validates unique name identities, dense expression
   IDs, backward expression edges, declaration kinds, and that every required
   dependency occurs in the original certificate. All 253,649 importer
   entries and 21,039,124 expression nodes are accounted for.
4. A file-owned group selects all original exported constants owned by that
   file. A whole-environment group selects the non-internal exported constants
   in that file's transitive module environment. Dependency reachability then
   includes needed internal helpers. Expression membership is propagated
   backwards through the certificate's shared DAG.
5. `validate.py` compares predictions with actual standalone exports for
   `Cslib.Computability.Automata.DA.Buchi`,
   `Cslib.Foundations.Control.Monad.Free.Fold`, and the combined CSLib roots.
   See `validation.json` for counts and commands. The combined export uses
   `ExportSelected.lean` to pass the original Lean `Name` objects to the
   existing exporter: some generated names do not round-trip through its CLI
   name parser.

An "entry" uses the same counting convention as the importer: one definition,
theorem, opaque declaration, axiom, or inductive type, plus one quotient
package. Constructors and recursors are handled as part of their inductive
families rather than additional entries. Rocq can generate multiple constants
or universe instances for an entry; those are not counted here. Repeated
foundation loading, name/universe data, serialization, and uneven kernel
conversion costs also prevent converting these factors directly into runtime.

All analysis and export workers used the existing shared memory guard with a
6 GiB hard limit. No Rocq checks, kernel edits, importer edits, or library
rebuilds were performed for this measurement.

## Artifacts and reproduction

- `summary.json`: exact totals, coverage, and multiplicity distributions.
- `groups.csv` / `groups.json`: per-file counts for both export methods.
- `provenance.json`: source revisions and input hashes, including CSLib source
  and compiled module files. The certificate hash is in `summary.json`.
- `validation.json`: independent export comparisons.
- `Cslib-selected-union.ndjson`: actual combined selected certificate.
- `parsed.pickle`: local cache of the parsed certificate; remove it if inputs
  change. It is only a measurement cache, not a checked Rocq artifact.

From the repository root, the analysis can be repeated with:

```bash
overlap_root="$PWD"
overlap_dir="$overlap_root/work/cslib-module-overlap-20260909"
export ROCQ_MAX_RSS_KIB=5767168 ROCQ_MEMORY_MAX_KIB=6291456
export ROCQ_MIN_AVAILABLE_KIB=3145728

cd "$overlap_root/_deps/lean-kernel-arena/_build/tests/work/cslib/src"
bash "$overlap_root/work/run-memory-guarded.sh" lake env lean --run \
  "$overlap_dir/Metadata.lean" "$overlap_dir/metadata.jsonl"
bash "$overlap_root/work/run-memory-guarded.sh" lake env lean --run \
  "$overlap_dir/Modules.lean" "$overlap_dir/modules.json"

cd "$overlap_root"
bash work/run-memory-guarded.sh python3 "$overlap_dir/analyze.py"
bash work/run-memory-guarded.sh python3 "$overlap_dir/validate.py"
```
