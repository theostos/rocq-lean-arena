# Audit obsolete checkpoint files before scoped cleanup

Base: `review/mathlib-repair-loop`.

Restrict cleanup to explicit legacy directories and Cslib*.vo candidates.
Record identity and source/artifact hashes; refuse changed or open files.
Preserve sources/logs and current checkpoints/seals. Deletion requires an
explicit apply step after the audit.

Tests use temporary files, including refusal cases. This commit does not run
cleanup or include historical deletion manifests, checkpoints or logs.

The active repair and running supervisor are unchanged by this review split.
