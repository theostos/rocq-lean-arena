# Reproduce Mathlib → Rocq

Run checked **100,001,405 export records, zero admissions**
with a modified Rocq kernel. ProofWidgets/Mathlib widget UI declarations are
excluded.
Recorded cost: **~11 hours on one core, ~30 GiB peak RAM**.

```bash
git clone --branch handoff/mathlib-20260919 https://github.com/theostos/rocq-lean-arena.git
cd rocq-lean-arena
# Optional: choose a disk with enough space (keep this set for all three commands).
export MATHLIB_REPRO_DIR="$PWD/_build/mathlib-repro"
bash scripts/mathlib_quickstart.sh build
bash scripts/mathlib_quickstart.sh export
bash scripts/mathlib_quickstart.sh check
```

`build` creates a dedicated OCaml 4.14.2 opam switch and builds Rocq, the required
Stdlib modules, and the importer. `export` builds pinned Mathlib, checks the export hash, and
audits/removes UI declarations. `check` starts at record 1, fails on any error
or timeout, and prints `PASS` only on success.
Progress: `tail -f "$MATHLIB_REPRO_DIR/check.log"`.
It runs in one process and saves no checkpoint.

Exact sources (the script pins full commit hashes):

| Component | Repository / branch | Commit |
| --- | --- | --- |
| Rocq | [theostos/rocq](https://github.com/theostos/rocq/tree/kernel/nested-conversion), `kernel/nested-conversion` | `01d35a1f01e5` |
| Importer | [theostos/rocq-lean-import](https://github.com/theostos/rocq-lean-import/tree/importer/survey-mode), `importer/survey-mode` | `643ff336974d` |
| Stdlib | `coq/stdlib` | `3e47b26f345f` |
| Lean Kernel Arena | `leanprover/lean-kernel-arena` | `4ce4d513d6f3` |
| lean4export | `leanprover/lean4export` (Lean override: `v4.29.0`) | `3de59f10bc4b` |
| Mathlib | `leanprover-community/mathlib4`, Lean `v4.29.0` | `8a178386ffc0` |

The importer runs with **survey mode disabled**.
Patch details: [SUBMISSION.md](SUBMISSION.md).
