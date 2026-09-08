# Queue the Mathlib repair loop after verified cslib completion

Base: `review/mathlib-export`.

Wait locally for cslib's verified EOF, seal and reload result. Follow explicit
cslib restarts and keep paused runs waiting. Only after successful handoff,
freeze the tested foundation, prepare Mathlib and enter its own repair session
using the shared single-heavyweight locks and checkpoint machinery.

Tests mock model/compiler activity. The real Mathlib queue is still waiting for
cslib; end-to-end Mathlib verification is not claimed.

The active repair and running supervisor are unchanged by this review split.
