# Standalone NDJSON branch audit — 2026-09-11

## Confirmed

An archive of importer commit `9a2326121fc1daedc90a60d990f8ebcca4ae899c`
was compiled independently of the CSLib/Mathlib integration branch. All OCaml
interfaces and implementations compiled, and packing/linking produced the
bytecode archive, native archive and native dynamic plugin. The compiler used
the generated-Makefile warning policy.

The Rocq OCaml runtime was rebuilt from the clean upstream worktree at
`56acfe11bcabfc81712ec0191bcbbd7c603e71e5`, not the patched kernel.
OCaml is 4.14.2. Yojson 3.0.0 was resolved through the existing isolated findlib
alias; no packages were installed or global configuration changed.

See `plugin-only.log` and `compile-only.sh`. Result: exit 0.
Plugin artifacts are in `../ndjson-pr67-20260909/plugin-build-F41ttrYa/`.

Exact source hashes:

```text
2ec29730cab23601ef83c53475e3f6a29de85e5b0a4f21a41e5daf5e06e79487  src/lean.ml
2b1b7b0acfedbe1df4d310a8a57ed873ab0699a36aca04b69db5d9c6c9120da7  src/leanExpr.mli
90f2e6cd9e839d080cbf85aa574f55078ee235ede06defac14c05d27dd45ad8d  src/leanParseNdjson.ml
```

## Not established

- Full `make` / compilation of `src/Lean.v` and registrations.
- Dynamic loading of the plugin in a Rocq worker.
- Execution of the branch's `.v` tests or a fresh-process import/reload check.
- Standalone CSLib or Mathlib support.

The full-test preparation (`run.sh`) was stopped before any proof-checking
worker started. The active Mathlib guard rejects simultaneous Rocq workers;
the user's approval to pause at a saved checkpoint was requested, but had not
arrived when this report was written. Mathlib was left running. The successful
`compile-only.sh` builds only Rocq's OCaml runtime, not Corelib or proof tests.

The first runtime-only build needed its OCaml C-stub search path restored
(`dllzarith.so`); the rerun succeeded. This was a validation-environment issue,
not an importer source change.

## Test coverage visible in the branch

Four NDJSON tests actually import/translate: `ndjson_bin_tree`, `ndjson_list`,
`ndjson_anomaly_print_projections`, and `ndjson_ulift`.
Six larger NDJSON fixtures use `Set Lean Just Parsing`: `core`, `init`,
`stdlib`, `logic`, `pnni`, and `quot`. Parsing-only success does not establish
kernel checking of their proofs.

The five zipped NDJSON fixtures are Git-LFS pointers in this checkout and
are not yet hydrated. A complete test run also needs those input files.
Earlier records under `../ndjson-pr67-20260909/` concern an earlier draft and
were parser-only/plugin-compilation checks, not an end-to-end runtime pass
of this exact published commit.

No importer or kernel source changes, commits, pushes, or Mathlib pauses were
made by this audit. Generated stock-runtime artifacts and this isolated source
snapshot were retained.
