This run does not reach the target and is NOT validation evidence.

The non-streaming legacy converter stopped with a sparse-level-ID error before
the final theorem. The importer then accepted that incomplete file's prefix.
The recorded process exit code is accurate but does not establish target success.

Use `slice-stream-baseline` instead: the streaming converter completed, retained
all dependency proofs, and reproduced the target's actual type-checking failure.
