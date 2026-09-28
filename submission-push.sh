#!/bin/sh
# Publish the complete feature stacks and the reproduction guide. No branch deletion.
# Run after enabling GitHub push authentication: sh submission-push.sh
set -e
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROCQ=$ROOT/_worktrees/rocq/compact-peano-view
IMP=$ROOT/_worktrees/rocq-lean-import/cslib-ndjson

git -C "$ROCQ" push --atomic origin 'refs/heads/kernel/*:refs/heads/kernel/*'
git -C "$IMP" push --atomic origin 'refs/heads/importer/*:refs/heads/importer/*'
git -C "$ROOT" push -u origin handoff/mathlib-20260919
