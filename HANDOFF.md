# Mathlib source handoff — 18 September 2026, Penrose update

Start here in the remote session. This is a reproducible **source snapshot**,
not a claim that all Mathlib passes or that the patched kernel is fully audited.

Follow-up to the original snapshot: the 55M–60M run stopped at Penrose line
58,521,284. A separate repair passed the exact proof replay, standalone target
check, ten native test groups, 18 focused fixtures and the prior Padic replay; see
[work/mathlib-penrose-repro/README.md](work/mathlib-penrose-repro/README.md).
Its validation receipt, when present, binds the completed qualification evidence
and the approved continuation from 55M. This is not a full Mathlib pass.
The follow-up is preserved in the separate `handoff/mathlib-20260918-penrose`
source branch, delivered to `homepc` through incremental Git bundles. It is
**not published to GitHub**. The original published branch remains unchanged.
The Penrose report and receipts retain their historical laptop paths and
pre-transfer wording; this handoff documents the later source transfer.

## What is saved

The original `handoff/mathlib-20260918` branch exists on GitHub in three
repositories. The SSH follow-up updates the arena and kernel only:

| Repository | Purpose / pinned revision |
| --- | --- |
| `theostos/rocq-lean-arena` | This handoff, runner sources, repro harnesses, review notes and small validation records. The SSH follow-up is a child of published snapshot `2abce41a8ebd9f4ec10959f42d2f4d1b01b6b55f`; the bundle's source receipt pins its new commit. |
| `theostos/rocq` | Updated kernel sources: `7b45cab763216a35b043afd356d1852f18e09b8d`. Six-file delta from original snapshot `d17b66af824e344393b126e57fbcec99174f926a`; original base: `f756383de2e66f63c95815c73838596d7d97c1c2`. |
| `theostos/rocq-lean-import` | Exact staged importer source: `5cf335ec68a41ad23dd720018a191f95b161a5cc`. Base integration: `d3e25df20a47bcc23fe539335e0b21652a59baca`. |

[docs/handoff-20260918.json](docs/handoff-20260918.json) pins the remaining
dependencies, export identity and validated local worker. Nested checkouts are
installed explicitly; they are not submodules and an ordinary `git pull` does
not update them. The snapshots use dedicated refs and do not rewrite old review
branches, the laptop's live branch, or its working index. Snapshot commits are
attributed to Codex; no user co-author trailers were invented.

The user chose to **regenerate binaries, exports and checkpoints** remotely.
No compiled runtime, opam switch, multi-GB export or checkpoint chain is being
copied. Small historical evidence is retained; old absolute paths inside those
records describe the producer machine and must not be rewritten as new results.

## On homepc

Target directory: `/home/theo/Documents/github/rocq-lean-typechecker`.
Host inspected: x86_64 Ubuntu 22.04, 188 GiB RAM, approximately 266 GiB free disk
at handoff preparation. The laptop uses Ubuntu 24.04: its native binaries require
GLIBC 2.38 and cannot simply be copied onto this host. Rebuild from source.

The source-only update bundles and their per-file receipts are in
`/home/theo/mathlib-handoff-20260918-penrose` on `homepc`. Neither the importer
source nor reference dependency revisions changed. No rebuild or remote run
is part of this transfer.

To provision another fresh machine, first install the **published baseline**:

```sh
git clone --branch handoff/mathlib-20260918 --single-branch \
  https://github.com/theostos/rocq-lean-arena.git rocq-lean-typechecker
cd rocq-lean-typechecker
python3 scripts/handoff/install_sources.py
python3 scripts/handoff/install_sources.py --check
```

Then copy the Penrose bundle directory from `homepc` and apply both incremental
bundles (the baseline commits above are required). In clean checkouts:

```sh
git -C _worktrees/rocq/compact-peano-view fetch /path/to/kernel.bundle \
  refs/heads/handoff/mathlib-20260918-penrose:refs/heads/handoff/mathlib-20260918-penrose
git -C _worktrees/rocq/compact-peano-view switch handoff/mathlib-20260918-penrose
git fetch /path/to/arena.bundle \
  refs/heads/handoff/mathlib-20260918-penrose:refs/heads/handoff/mathlib-20260918-penrose
git switch handoff/mathlib-20260918-penrose
python3 scripts/handoff/install_sources.py --check
```

A GitHub pull alone does **not** include this SSH-only update. The existing
source installer refuses mismatched revisions; do not reset local work to
bypass it. The final `--check` verifies the updated kernel pin.

The installer clones pinned source checkouts without touching existing unrelated
directories. It restores the exact diagnostic stream converter, and pins
lean4export to Lean 4.29. It does **not** compile, modify the default opam switch,
launch a Mathlib run, or download LFS dump fixtures. LFS fixtures can be fetched
explicitly if required for their tests; they are not needed to compile the importer.

The separate historical evidence archive on `homepc` is at
`/home/theo/mathlib-handoff-20260918/evidence.tar.gz`; its extracted files are in
the adjacent `evidence/` directory. It includes per-file hashes and the three
source snapshot receipts. From this checkout, verify it with:

```sh
python3 scripts/handoff/package_evidence.py verify \
  /home/theo/mathlib-handoff-20260918/evidence.tar.gz
```

This archive contains small records/logs only, not a resumable checkpoint.

## State of the experiment

The current generation has successfully compiled, saved and freshly reloaded
the contiguous prefix through **55,000,000 / 100,001,405 NDJSON records**.
It began from line 1 and has used validated worker migrations; it is not a fresh
line-1 check entirely on the last worker. The laptop was checking the 55M–60M
chunk when this handoff was prepared. Its run was not stopped by this handoff.
Record counts are not counts of theorems, nor a workload-weighted percentage.

Latest fix: the Penrose proof at line 58,521,284, described above. The exact
compiler replay passed in 660.31 seconds and fresh standalone target checking
in 587.80 seconds. The local loop was restarted from 55M with the same resource
and proof policies. The full export has not yet been validated.

Previous fix: `PadicInt.coe_adicCompletionIntegersEquiv_apply`, line 54,302,445.
The original proof-preserving replay now checks the declaration in about 11.65
CPU seconds (80.68 s including load/save), versus the original production timeout
of 1800 seconds. Independent **target-only** checking, 16 native fixtures and
the direct inversion-control unit passed. See
[the Padic report](work/mathlib-padic-repro/README.md) and its validation receipt.
No complete independent recheck of Mathlib, minimality proof of the patch set,
formal soundness proof, or full Lean/Rocq judgment equivalence is claimed.

## Rebuild order (remote build has not been executed yet)

1. Create an **isolated** opam switch; leave the host's existing default switch
   alone. Producer versions: OCaml 4.14.2, Dune 3.23.1, ocamlfind 1.9.8, Zarith
   1.14. Also install Yojson and the build dependencies in the pinned Rocq
   `INSTALL.md`. The running importer is the serial OCaml 4 pipeline, not PR #78.
2. Build the pinned Rocq checkout (runtime, core library, checker and plugins).
   Use that same OCaml toolchain and kernel interfaces for every plugin. Follow
   its `INSTALL.md`/Dune build instructions; the scripts expect its development
   prefix at `_build/install/default`.
3. Build stdlib commit `3e47b26f...` against this kernel into the checked-out
   stdlib's `theories/` layout. Build the pinned importer using the resulting
   `rocq makefile`, `COQBIN` and `OCAMLPATH`. The old
   `work/kernel-alignment-pass/build-importer.sh` is historical: it hard-codes
   laptop opam paths, notably `coq820_dev/lib/yojson`. Adapt those locations for
   the new switch rather than installing the laptop's switch names blindly.
4. Run focused kernel/importer checks and a small save/reload import. Capture
   **new** binary hashes and a new validation record. Old worker/receipt hashes
   remain historical evidence, not approval for a newly built binary.
5. Regenerate the pinned reference export with the pinned arena and exporter.
   Build the preinstalled exporter first (`lake build` in its directory), then
   run `uv run lka.py build-test mathlib` from `_deps/lean-kernel-arena`.
   This is a large build/export. Inspect its NDJSON header, statistics and hash
   against the handoff manifest. If bytes differ, investigate or create a new
   export generation; never reuse historical line positions/checkpoints blindly.
6. Prepare a **fresh** checkpoint generation, with the new importer, foundation,
   worker, debugger and source hashes. Start from line 1. The relevant runner is
   `scripts/mathlib_ndjson_loop.py` (direct NDJSON), not the older 4.27
   `scripts/prepare_mathlib.py`. Its base CLI permits 16 GiB; the laptop used a
   separately recorded 25-decimal-GB override. Explicitly configure and record
   the remote budget; do not silently reuse the laptop's approval/certificate.

The intended checking policy is unchanged: Fail mode, no missing-quotient skips,
no parsing-only or lazy-instantiation mode, 1800 s per declaration, 5M-record
checkpoints, fresh reload verification, no workload swap. Host RAM availability
does not itself authorize changing proof checking or enabling diagnostic bypasses.

Do not run the Padic or Penrose `work/*/resume.py release` scripts on a fresh
machine: they are deliberately tied to the laptop's artifacts and producer seals.
Do not modify any old seal or hash to make a mismatch disappear.

## Review and what to preserve

Read [the current review map](docs/mathlib-handoff-review.md), then the historical
alignment review and implementation reports linked there. Source snapshots are
the authority for what is included; individual test receipts state which worker
was actually validated. Some earlier checkpoints were deleted on request, so
their hashes/results remain, but the compiled files must be regenerated.

The next session should first verify the source layout, then build and qualify
the remote runtime. No remote production run has been started as part of this
source-only handoff. When deciding to move computation, coordinate stopping the
laptop explicitly; do not infer that this document stopped it.
