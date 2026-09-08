# Prepare pinned Mathlib exports with streaming and provenance checks

Base: `review/cslib-repair-loop`.

Select the Lean 4.27.0-rc1 Mathlib checkout matching cslib. Verify source and
exporter provenance, stream NDJSON into the converter and promote only after
both processes succeed. Require memory/disk admission and a pinned toolchain;
prepare isolated full and smoke exports with unseeded 2M checkpoint plans.

Tests use tiny subprocesses and fake source trees. The real Mathlib export and
full import have not run yet. No library export/cache/checkpoint is committed.

The active repair and running supervisor are unchanged by this review split.
