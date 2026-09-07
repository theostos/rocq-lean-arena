# Guard checker entry points and serialize heavyweight jobs

Base: `review/export-hints`. Compare against this base, not upstream.

Route checker builds/runs and frontier probes through a single user-wide cgroup memory guard. Test process liveness, service ownership and wrapper cleanup with fake commands, not a live Rocq workload. This addresses the earlier concurrent-worker and out-of-memory incidents.

## Validation

Not rebuilt at this split head. Earlier checks cover the combined experimental sources, not this intermediate branch.

This is an experimental review branch, not a claim of a complete cslib check.
