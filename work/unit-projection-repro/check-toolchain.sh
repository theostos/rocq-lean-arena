#!/usr/bin/env bash
set -Eeuo pipefail
repro_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$repro_dir/../.." && pwd -P)
cd -- "$repo_dir"

# This pins the unit-projection, direct-dependency, compact-fuel, wrapper, eta-fallback
# and congruence-probe scope/bounded-congruence fixes,
# not a general digest override.
# Keep the old manifests as evidence of how the prefix was produced.
sha256sum --check --strict <<'EXPECTED'
d338d5ec581d16f710e5ff43f7d1d8a38206e84a6c40bc3cfd16bccc007a0248  _worktrees/rocq/compact-peano-view/_build/default/topbin/rocqworker.exe
f575aff26f6e50d3e1c036b1c1f3cb9c3040387101c9ff4faca39cc791ca37b5  work/cslib-full-fresh/runs/cslib-unit-fix/prefix.sha256
97dd72a678bc5595b92e336671972d84581956cfd3cb84d9c66d468806c734be  work/cslib-full-fresh/runs/cslib-unit-fix/inputs.sha256
EXPECTED
run_dir=$repo_dir/work/cslib-full-fresh/runs/cslib-unit-fix
sha256sum --check --strict "$run_dir/prefix.sha256"
# The pinned original manifest contains the old worker hash. Every other
# original input, including the importer and foundation, must remain identical.
awk '$2 !~ /\/topbin\/rocqworker.exe$/ { print }' "$run_dir/inputs.sha256" |
  sha256sum --check --strict
