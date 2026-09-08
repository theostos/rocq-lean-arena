# Run guarded compilation locally and invoke bounded repair on failure

Base: `review/checkpoint-generations`.

A systemd supervisor owns guarded compilation and local waiting. Invoke GPT-6
Astra with xhigh reasoning only for actionable declaration failures, then run
independent gates. Repairs may build and run regressions, but not monitor or
launch the full pass. Preserve the dedicated session and bounded repair count.

The explicit --retry-validation path reruns a reviewed candidate's gate without
a model turn, preserving its original result. Representation changes force a
fresh chain; compatible kernel migrations may resume. Tests mock external work.
Full-local repair access is opt-in, not filesystem isolation. Runtime sessions,
logs, credentials and checkpoints are excluded.

The active repair and running supervisor are unchanged by this review split.
