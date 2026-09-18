# PR 67 parser regressions

External, parser-only test harness. The baseline source and small real fixtures
are snapshots of importer `upstream/pr-67`, commit
`1854c19a744b4459f3b614308971af1fbdbb296d`.

Run baseline:

```sh
bash work/ndjson-pr67-20260909/run.sh
```

Run the current candidate after its author says editing is ready:

```sh
bash work/ndjson-pr67-20260909/run.sh \
  _worktrees/review/importer-ndjson-20260909
```

The runner compiles only five parser-side modules and tiny tests to a fresh
`build-*` directory here. It does not compile the importer plugin, launch Rocq,
install packages, or unpack large dumps. Each executable has a 30-second timeout.
It uses OCaml 4.14.2 and existing stock-runtime libraries, plus an isolated
findlib META alias to the existing OCaml-4.14.2 Yojson 3.0.0 installation.

Baseline: structural tests 10/41 pass, 31 fail; legacy hint probes 1/4 pass,
3 fail. Full assertion output is in `baseline-results.tsv`.
The candidate automatically selects `ndjson_hint_tests.ml` when `kernel_opaque` appears in
`leanExpr.mli`; otherwise the probes in `baseline_hints.ml` document lost
distinctions in the old representation.

Negative-reference tests require a `CErrors.UserError`, not an implementation
exception. Constructor checks mutate the real `bin_tree.ndjson` declaration,
retaining the full canonical payload shape and all unrelated fields.

The extended candidate suite includes prefix dictionary preservation and
dense/sparse interleaving tests. Its output is `candidate-final-results.tsv`.
The separate serial bytecode/native plugin-only build is documented in
`plugin-check-results.md`; the source snapshot and all artifacts remain here.
