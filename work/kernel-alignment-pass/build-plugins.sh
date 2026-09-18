#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_dir=$(cd -- "$test_dir/../.." && pwd -P)
kernel_dir=$repo_dir/_worktrees/rocq/compact-peano-view
export PATH=/home/theo/.opam/rocq93_native/bin:$PATH
export ROCQ_MAX_RSS_KIB=1835008 ROCQ_MEMORY_MAX_KIB=2097152
export ROCQ_MIN_AVAILABLE_KIB=6291456 ROCQ_MEMORY_SWAP_MAX_KIB=0
mapfile -t targets < <(cd "$kernel_dir/_build/default" &&
  if command -v rg >/dev/null 2>&1; then
    rg --files --no-ignore plugins -g '*.cmxs'
  else
    # Background systemd jobs do not inherit VS Code's bundled tool directory.
    find plugins -type f -name '*.cmxs' -print
  fi)
if (( ${#targets[@]} == 0 )); then
  printf '%s\n' 'No existing plugin targets found' >&2
  exit 1
fi
exec bash "$repo_dir/work/run-memory-guarded.sh" \
  timeout --signal=TERM --kill-after=5s 300 \
  dune build --root "$kernel_dir" -j1 "${targets[@]}"
