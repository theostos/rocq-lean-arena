# Obsolete Mathlib checkpoint cleanup

Completed 2026-09-11 at the user's request to remove as many unused checkpoints
as possible. Removed **868 compiled `.vo` / `.vo.gz` files**, reclaiming
**5.792 GiB**. Free space immediately afterward was **10.508 GiB**.

Removed the 18 obsolete `MathlibTo*Reload.vo` outputs for 1M through 18M,
and superseded Mathlib diagnostic/replay/regression binaries in the explicitly
listed investigation directories. The earlier compressed replay checkpoints
were also deleted, not merely moved elsewhere on the same filesystem.

Preserved:

- All **19 incremental main checkpoints**, their sources and seals. Earlier
  main checkpoints remain dependencies of the later ones and cannot be pruned.
- The latest 19M reload and progress record.
- The complete approved `mathlib-basic-open-repro/validation-8gccux_c` batch,
  its required sources and its external staged kernel fixtures.
- Foundations, all source files, logs, result records, and worker binaries.
- CSLib checkpoints and unrelated development/export data.

`plan.json` records every exact target, SHA256, size and retained rebuild source.
`removed.jsonl` records each completed deletion. `result.json` records measured
disk usage. **367 protected files** were verified byte-for-byte unchanged.
`resume.sh --check` passed before and after deletion. The disk-paused service
`rocq-mathlib-ndjson-closure-syntax.service` was restarted from its sealed 19M
checkpoint after cleanup; its normal checkpoint verification and resource guards
remain enabled.

Deletion is permanent: these binaries are not in trash or a backup. Rebuild them
from the retained source/runner if needed (including any removed replay prefixes
first). Historical validation records remain evidence of the earlier runs, but
their superseded resume gates may now require rebuilding the removed artifacts.
The current resume gate is intact.

`cleanup.py` refuses a second application once the deletion journal exists.
It holds the common launcher lock, refuses concurrent Rocq workers, validates
the complete inventory before deletion, and only unlinks individual regular
files. It does not perform recursive directory deletion.
