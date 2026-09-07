# Extraction record

These are the one-time scripts used to cut the September 7 review branches.
They are retained as an audit record, not as a supported build command: paths
and source-hunk coordinates refer to the captured local worktrees. Re-running
requires that exact input. Do not run them in an unrelated checkout.

`package-cslib-review.py` uses temporary Git indices and checks runtime-source
equivalence; it does not switch or modify the active implementation worktrees.
`check-cslib-review.py` performs sequential OCaml source checks against the
already built experimental interfaces, not full Rocq builds.
