# Seal and resume immutable checkpoints

Base: `review/atomic-checkpoints`.

Keep producer hashes separate from current migration checks. Reuse a saved
checkpoint only when its seal, sources and toolchain inputs match. Preserve
atomic promotion and the shared memory/worker guards. The legacy 15M launcher
and explicit migration checker are included as historical experiment tooling,
not portable fresh-install commands.

This commit contains no compiled checkpoints, binary tools, runtime seals,
credentials or full-library exports. Tests use temporary fake artifacts.
The active repair worktree and running supervisor were not modified.
