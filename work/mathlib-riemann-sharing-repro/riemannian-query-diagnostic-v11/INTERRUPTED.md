# Diagnostic only: deliberately stopped before saving

At 18:02 CEST on 2026-09-15, the prepared-prefix run reached the import's
post-checking checkpoint phase (`before checkpoint GC cpu=372.977`). The
assistant stopped only `rocq-mathlib-riemann-diagnostic-v11.service` and its
bound guard scope to avoid spending time/space saving another diagnostic
artifact. The conversion-entry and application-cache logs are preserved.

There is no completed `.vo` certificate from this run. It must not be used
as a validation stage or as production restart approval. In particular, the
uninterrupted v11 replay still failed at 25,505,940. Reloading this prepared
prefix changes the performance behavior and does not reproduce that failure.

The worker was 9cc329f53f980bc400264c1a82f80b9cc8c2fbc2e112787c8f057dfefff81462.
The separate declared-order prototype was edited and privately tested during
this diagnostic, but was not built into or used by this running worker.
