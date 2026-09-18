# Candidate plugin-only compilation

After rebasing `submit/ndjson` onto upstream `0483fe4`, both checks passed:

```sh
bash work/ndjson-pr67-20260909/plugin-check.sh \
  _worktrees/review/importer-ndjson-20260909
```

This produced `plugin-build-CTr1F0PH/lean_import.{cma,cmxa,cmxs}`. The rebased
`lean.ml` hash is `8720bfe39a9aade5e2e00f0220c1a3a84690867355a8bb5e96f483e679ac878e`.
The other two hashes below are unchanged.

The generated Makefile also built the bytecode archive and native plugin:

```sh
make --no-builtin-rules -f Makefile.rocq -j1 \
  COQTOP=false COQC=false COQNATIVE=false \
  src/lean_import.cmxs src/lean_import.cma
```

Both commands used the isolated stock runtime prefix from `plugin-check.sh`,
a 1 GiB address-space limit, a 60-second CPU limit and a 90-second timeout.
Makefile generation confirms the committed META file and Yojson compiler flags
are recognized. Its dependency scan warned about the absent stock Stdlib in
this runtime-only installation. No `.v` files were compiled.

## Earlier snapshot build

Passed `timeout --signal=TERM --kill-after=3s 90 bash work/ndjson-pr67-20260909/plugin-check.sh`.

Compiled all interfaces and implementations, including `lean.ml`, in bytecode
and native modes with the generated-Makefile warning policy. Preprocessed
`g_lean.mlg`, packed the modules, and built all three plugin artifacts:

- `plugin-build-qcmX7Jlh/lean_import.cma` (119 KiB)
- `plugin-build-qcmX7Jlh/lean_import.cmxa` (8.9 KiB)
- `plugin-build-qcmX7Jlh/lean_import.cmxs` (404 KiB)

Source snapshot: `plugin-snapshot/src`. Its key SHA-256 values before the rebase:

```
109c7bdd7b7e40c7e6d277a7acf28731f0cf815777029982c6abe479ad4a7bdc  lean.ml
2b1b7b0acfedbe1df4d310a8a57ed873ab0699a36aca04b69db5d9c6c9120da7  leanExpr.mli
636cf5c99b3d687240acc1debd61956dec648e69878b286b213bd3fda5a4bcb3  leanParseNdjson.ml
```

The only build warnings were findlib detecting the stock runtime's package
before the older opam-switch runtime; resolution selects the stock runtime.
No `.v` targets or Rocq workers were run. The `rocq pp-mlg` shim directly invokes
`Coqpp_main.main` (confirmed from stock runtime `topbin/rocq.ml`). No plugin was
dynamically loaded; this verifies compilation/linking, not runtime translation.

CI audit correction: this candidate does not need an LFS checkout. Its only LFS
path is `dumps/mathlib.out.zip`, which the tests do not use. The recorded PR #67
failure was `Unbound module Summary.Ref` on an older Rocq development image;
upstream master now builds with the same API on the current image. This does
not establish that the candidate's full integration tests pass.
