# Repository disk audit — 2026-09-13

## Cleanup completed

After user approval, **155,109 inactive artifact files were removed**, reclaiming
**41.36 GiB** of allocated regular-file storage (accounting for surviving hard
links). Repository usage is now approximately **27 GiB**, down from about 68 GiB;
the filesystem has roughly **48 GiB available**.

The current Mathlib service remains running with the same PID. **All 722 protected
input checksums passed**, including the full active Mathlib NDJSON and pinned
toolchain inputs. Dirty tracked-source checksums were unchanged. No worktrees,
source checkouts, ordinary Git objects/packs, or active checkpoints were removed.
Git now reports zero temporary garbage.

Deletion covered 64 abandoned Git temporary files, 35 large old exports, three
interrupted exports, 129 obsolete checkpoint files, inactive caches/binaries,
10 generated index files and historical logs. The 41.5 GiB selected estimate
became 41.36 GiB actually reclaimed because some hard links were retained.
Small regression inputs, source-like files, changed files and protected evidence
were excluded.

There is **no trash/recovery copy**. Generated artifacts can be rebuilt or
re-exported from preserved sources; old compiled checkpoint chains must be
recreated. Removed historical logs and incomplete temporary files cannot be
recovered from the journal. Future Lean/CSLib workflows may require rebuilding
their caches or re-exporting their inputs.

- `removed.csv.gz`: exact deletion journal with sizes and original file identities.
- `cleanup-result.json`: removal counts and source-check results.
- `verification.json`: protected-input integrity checks and reclaimed bytes.
- `approved-candidates.csv.gz` / `skipped.csv.gz`: reviewed selection/exclusions.
- `cleanup.py` / `verify.py`: scoped cleanup and verification scripts.

The original audit below is retained for historical context; its candidate lists
and “no deletion” statement describe the state **before** this cleanup.

## Result

The repository occupied approximately **67.6 GiB** during the audit (rounded to
68G by `du`). There are **42.9 GiB of cleanup candidates**, with different costs
and prerequisites described below. This is an inventory, **not a blanket-safe
deletion list**. No pre-existing files were deleted by this audit.

The running Mathlib job, its checkpoint chain, exported input, current kernel,
stdlib and importer were explicitly excluded. All tracked files and unclassified
source/data files were also excluded from the file-level candidate list.

## Non-overlapping file categories

| Category | Allocated GiB | Consequence / recommendation |
|---|---:|---|
| Git temporary objects/packs | 10.51 | First cleanup target. 64 files reported as garbage by `git count-objects -vH`. Recheck for an active Git writer/open descriptor immediately before removal. Do not delete ordinary Git objects or packs. |
| Interrupted exports | 0.35 | Three incomplete `.lean-export.tmp.<pid>` files from July. Remove after checking they remain unused. |
| Obsolete import checkpoints | 1.35 | 129 compiled files outside the protected generation; loses old resume chains, not source. Keep `.v` files, logs and seals as historical records. |
| Inactive build caches | 9.56 | Lean/Lake and compiler build outputs. Re-download/rebuild before using those tools/libraries again. |
| Other compiled artifacts | 5.91 | Experimental executables, OCaml objects, compiled proofs and related files. Includes additional CSLib proof snapshots. Regenerate before replaying old experiments. |
| Completed exports — review before deleting | 13.22 | Old full exports and smaller experiment inputs. Not needed by the current Mathlib job, but other regression/CSLib workflows may still need them; preserve generation recipes/provenance. |
| Derived distributed-import index | 1.14 | Recreate the index before running that older distributed-import experiment. |
| Historical logs — optional | 0.85 | Loses diagnostic evidence. Compressing selected logs is an alternative. Latest repair/validation evidence is protected. |
| **Total candidates** | **42.88** | Excludes protected files; not all categories have the same recovery cost. |

## Largest concrete targets

- `.git/objects/pack/tmp_pack_*` and two `.git/objects/*/tmp_obj_*` files:
  **10.51 GiB** combined. Git reported 64 garbage files. No active Git pack writer
  or open file in the pack directory was observed during the audit; that is a
  point-in-time check, not a permanent guarantee. The full exact list is in the
  `git-temporary` rows of the candidate inventory.
- `_deps/lean-kernel-arena/_build/tests/work/mathlib/src/.lake/build/`:
  **6.1 GiB**. Lean's compiled Mathlib cache, not the Mathlib source checkout.
  The active Rocq job reads NDJSON and does not need this cache. Future Lean
  checks/exports require downloading or rebuilding it.
- `work/library-exports/mathlib-4.29/full/Mathlib.lean-export`:
  **2.79 GiB**. Preserve `provenance.json`; regenerate if needed.
- `_deps/lean-kernel-arena/_build/tests/mathlib.lean-export`:
  **2.79 GiB**. An older completed stream, **not** the active `mathlib.ndjson`.
  The two large `.lean-export` files are not assumed byte-identical.
- `_deps/lean-kernel-arena/_build/tests/cslib.ndjson`: **1.21 GiB**.
  Optional: needed to run the corresponding CSLib workflow without re-exporting.
- `work/distributed-import-implementation-20260909/full-index/`:
  **1.14 GiB**. Ten generated index files, listed individually in the inventory.
- Old checkpoint generations `work/mathlib-alignment-5m-20260912/checkpoints/`
  and `work/mathlib-alignment-5m-20260913/checkpoints/`: **about 703 MiB** together.
  These are distinct from the active `...20260913-with-terminal/` generation.
- `work/cslib-full-fresh/runs/cslib-unit-fix/`: four large `.vo` files total
  **about 846 MiB**; retain its source/logs if discarding compiled proof snapshots.

There are also removable outputs spread across many small experiment folders.
Use the file inventory instead of deleting all of `work/`: it contains unique
untracked scripts, reproducers, reports and source changes.

## Worktrees: a separate, overlapping cleanup option

The audit found **69 clean top-level worktrees**, occupying approximately
**5.90 GiB**. Many duplicate the importer's tracked fixture archives. Removing
unused clean worktrees can reclaim these checkout copies, but this figure
**overlaps** the compiled-artifact/cache categories above; do not simply add it
to 42.88 GiB.

Use `git worktree remove <exact-path>` through the owning repository, not a
blanket recursive delete. Before removing a detached worktree, ensure its HEAD
has a retained reference if it is needed for recovery. Confirm ignored files
and other workflows are not needed; a clean `git status` alone does not establish
that. The list and status of all 155 detected repositories/nested checkouts is
in `repositories.json`.

**Never blanket-delete `_worktrees/`.** In particular,
`_worktrees/rocq/compact-peano-view` contains extensive uncommitted kernel changes
and untracked regression tests, as well as the running compiler.

## Protected current Mathlib run

At audit time, `rocq-mathlib-alignment-5m-20260913-thin-skeleton.service` was active,
working on the 15M–20M interval. This was checked to identify cleanup dependencies,
not to start continuous monitoring.

Protected paths include:

- `work/mathlib-alignment-5m-20260913-with-terminal/` — all checkpoints,
  reloads, staging files, manifests, logs and foundation.
- `_deps/lean-kernel-arena/_build/tests/mathlib.ndjson` — **5.3 GiB**, active input.
- `_worktrees/rocq/compact-peano-view/` — current kernel sources and binaries.
- `_worktrees/rocq/stdlib-int32-repro/` — active stdlib.
- `work/kernel-alignment-pass/importer.lFy9zJVL/` — pinned importer.
- `work/kernel-alignment-pass/final-gates-21/` and
  `work/mathlib-thin-skeleton-repro/` — latest validation/repair evidence.
- Every repository-local file pinned by the active generation's `toolchain.json`.

The active checkpoint files occupy roughly **0.9 GiB** at this point and form a
dependency chain. Keeping only the newest checkpoint is insufficient. Deleting
all of them requires deliberately abandoning/restarting the current run; they
were therefore not treated as inactive cleanup candidates despite the user's
willingness to discard checkpoints generally.

The remaining ordinary `.git` objects, packs, refs, reflogs and LFS data are not
garbage merely because they are large. Do not manually delete them or run a
history-rewriting cleanup as part of this file cleanup.

## Machine-readable reports

- `candidates.csv.gz`: every candidate file, ordered largest first; columns are
  category, allocated bytes, apparent size, relative path, inode/device, mtime and
  link count. A category is a review recommendation, not an executable deletion
  instruction.
- `files.csv.gz`: all **394,057 regular files** inventoried, including retained
  and protected files. Symbolic links were not followed.
- `groups.csv`: candidate/retained totals by directory and category.
- `repositories.json`: Git HEAD and complete tracked/untracked status per checkout.
- `summary.json`: exact totals and protection rules.
- `audit.py`: the read-only scanner used to produce the inventory.

Allocated sizes count a hard-linked inode only once. Symlinks, directory blocks,
files created after traversal and live-run growth can cause small differences
from later `du`/`df` results. The inventory is not a frozen snapshot: revalidate
file identity and active-process use before applying a deletion list. Historical
paths can appear in old seals/logs; deleting artifacts retires those histories'
ability to resume even when the records themselves are retained.
