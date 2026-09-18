# Importer branch cleanup — 2026-09-08

See [the current compatibility list](../../docs/importer-patches.md).

- `before.json`: all original refs and worktree statuses, including the fork.
- `importer-before.bundle`: complete Git history, verified before deletion.
- `bundle.sha256`: bundle integrity check.
- `worktrees/`: tracked dirty files, staged/unstaged patches and index snapshots.
- `plan.json`: exact retained and removed branch names and original tips.
- `archive-refs.json`: archive tag names and original commits.
- `published.json`: published replacements and remote archive tags.
- `detached-worktrees.json`: old checkout branches, unchanged HEADs, index hashes and statuses.
- `after.json`: final counts and verification result.
- `validation-audit.json`: retained branch tips checked against successful test records.

The cleanup changes branch references. It does not remove checkouts, reset
files, resolve/abort existing merges, rebuild binaries, or change checkpoints.
PR #70 stays open and its branch tip stays `96ff81d`. The two local exceptions
are the unresolved primary `arena-fixes` checkout and the configured
`integration/generic-cslib-current` runtime branch.

Restore a removed local branch from its local archive tag:

```sh
git -C _deps/rocq-lean-import branch recovered/old-topic archive/2026-09-08/local/pr/nested-containers
```

Restore from the bundle if the local archive tags are unavailable:

```sh
git -C _deps/rocq-lean-import fetch ../../work/importer-cleanup-20260908/importer-before.bundle refs/heads/pr/nested-containers:refs/heads/recovered/nested-containers
```

Removed fork heads have published tags under
`archive/2026-09-08/fork/<old-branch>`. To restore one remotely, first create a
local recovered branch at that tag, then push it to the desired fork branch.
The local bundle also preserves the previous master tips; both masters are
fast-forwarded to upstream `c8db093` during cleanup.
