#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
# Only generated, superseded artifacts from this investigation. Never touch
# the baseline, selected worker, active prefix, or canonical checkpoints.
artifacts=(
  rocqworker.bounded-copy.exe rocqworker.clean-first.exe
  rocqworker.data-constructor.exe rocqworker.fast-relevance.exe
  rocqworker.fast-stats.exe rocqworker.fast-syntax.exe
  rocqworker.fast-work-budget.exe rocqworker.keep-constructor.exe
  rocqworker.no-copy-stats.exe rocqworker.path.exe
  rocqworker.relevance-first.exe rocqworker.selective-memo.exe
  rocqworker.small-fast.exe rocqworker.type-control.exe rocqworker.unit-control.exe
  no-copy-normal/Target.vo
  validation-0xdvrudn/full/MathlibTo19000000.vo
  validation-0xdvrudn/reload/Reload.vo
)
for artifact in "${artifacts[@]}"; do
  [[ -f $artifact && ! -L $artifact && ! -e $artifact.gz ]] || {
    printf 'Unexpected artifact state: %s\n' "$artifact" >&2
    exit 1
  }
done
for artifact in "${artifacts[@]}"; do
  gzip --keep -- "$artifact"
  gzip --test -- "$artifact.gz"
  cmp -- "$artifact" <(gzip --decompress --stdout -- "$artifact.gz")
  unlink -- "$artifact"
  printf 'Archived and byte-verified: %s.gz\n' "$artifact"
done
