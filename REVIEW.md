# Plan sealed imports in resumable two-million-line chunks

Base: `review/checkpoint-resume`.

Plan declaration-safe chunks, preserve mutual-inductive blocks at boundaries,
seal each result and reload it in a fresh process before recording progress.
Resume the newest contiguous verified checkpoint. Require verified EOF, not
just a successful partial import. Resource and disk failures stop safely.

Tests use tiny fake exports and compiler stubs, without Lean, Rocq or models.
Real full-library exports/checkpoints are excluded.

The active repair and running supervisor are unchanged by this review split.
