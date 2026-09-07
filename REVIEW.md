# Promote checkpoints atomically and audit full-pass evidence

Base: `review/guarded-runs`. Compare against this base, not upstream.

Keep the last good .vo until its guarded replacement succeeds. Record source/toolchain hashes, require expected EOF and a successful save, and keep fresh-process reload as a separate gate. Includes the exact experimental launchers under work/: those pin local binaries/checkpoints and are not portable fresh-install instructions.

## Validation

Not rebuilt at this split head. Earlier checks cover the combined experimental sources, not this intermediate branch.

This is an experimental review branch, not a claim of a complete cslib check.
