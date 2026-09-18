# Mathlib: manual checking from line 1

From the repository root:

```sh
python3 scripts/run_mathlib_from_start.py --dry-run
python3 scripts/run_mathlib_from_start.py
```

The runner uses the same existing experimental kernel, importer and Rocq
libraries as the manual cslib runner. It does not build or switch them, and
does not use the untested `review/binary-peano` branch.

It reuses the Arena reference NDJSON already in
`_deps/lean-kernel-arena/_build/tests/mathlib.ndjson`: Lean `4.29.0`, Mathlib
`8a178386ffc0f5fef0b77738bb5449d50efeea95`. No Lean build or new export is needed.
The reference specification, NDJSON header and export statistics are checked;
a missing or mismatched reference is refused, not replaced with another version.

The old `mathlib.lean-export` dropped reducibility hints (`abbrev` and `regular`
became `#DEF`), so the runner reconverts the NDJSON once with the current
streaming converter. It leaves the original files untouched and publishes the
new conversion only after success and input-hash checks. Later invocations
verify and reuse this cache, but always check from line 1 with a fresh Rocq
foundation.

One memory guard covers preparation and compilation: 16 GiB hard limit,
15 GiB RSS limit, 3 GiB system reserve and no workload swap. The runner
refuses concurrent guarded jobs or another Rocq worker. Wait for cslib's
successful final exit before launching it. There are no checkpoints,
automatic retries, background supervisors or model calls.

Watch progress in another terminal:

```sh
tail -n 5 -F work/mathlib-from-start/latest/guard.log \
  work/mathlib-from-start/latest/Full.run.log
```

Reference verification and conversion appear in `guard.log`; `Full.run.log` is created when
Rocq starts checking Mathlib. The final result is:

```sh
cat work/mathlib-from-start/latest/result.json
```

Success requires exit code zero and `Full.vo`; `Done!` alone is insufficient.
Ctrl-C cancels the guarded job. Each invocation uses a new run directory;
cslib's logs and `latest` link are untouched.

The converted export lives in `work/library-exports/mathlib-4.29/full`. A mismatched cache
is refused, never silently overwritten. Failed `.full.stage-*` directories
are retained for diagnosis. Conversion admission requires 12 GiB free and keeps
a 3 GiB reserve while streaming; leave additional room for the final `.vo`.
The existing 5.3 GiB NDJSON is read in place, not copied.
These checks do not guarantee enough disk for the complete compiled result.

`--memory-mib` (up to 16384) and `--line-timeout` (up to 600 seconds) accept
the same limits as the cslib runner. `--directory` selects a new output
directory. The default declaration timeout is 600 seconds.

Launcher tests use mocks only; they do not establish a successful Mathlib import:

```sh
python3 -m unittest discover -s scripts/tests -p 'test_run_mathlib_from_start.py'
```
