# Index the importer, kernel and pipeline review stacks

Base: `review/isolated-loop-tests`.

Start with [docs/review-map.md](docs/review-map.md). It lists topic branches,
predecessors, motivating failures and validation limits. Exact commit hashes
are recorded in [docs/review-stack.json](docs/review-stack.json).

The UTF-8 investigation separates observed checkpoint behavior and conversion
traces from the still-unproven history of the regression.

Documentation only. No runtime state, checkpoint, binary or full export is
included. The preceding tip passed 169 unit tests, with two opt-in integration
tests skipped. Newly split compiler heads have not been rebuilt in isolation.
