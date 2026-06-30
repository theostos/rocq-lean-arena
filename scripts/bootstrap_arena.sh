#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
arena_dir="${ARENA_DIR:-$repo_root/_deps/lean-kernel-arena}"
arena_url="${ARENA_URL:-https://github.com/leanprover/lean-kernel-arena.git}"
arena_ref="${ARENA_REF:-4ce4d513d6f38614d801ab95e4ac069fb3740b0d}"

if [[ ! -d "$arena_dir/.git" ]]; then
  mkdir -p "$(dirname "$arena_dir")"
  git clone "$arena_url" "$arena_dir"
fi

git -C "$arena_dir" fetch --tags origin
git -C "$arena_dir" checkout "$arena_ref"

cp "$repo_root/checkers/rocq-lean-import.yaml" "$arena_dir/checkers/rocq-lean-import.yaml"
rm -rf "$arena_dir/checkers/rocq-lean-import"
mkdir -p "$arena_dir/checkers"
cp -R "$repo_root/checkers/rocq-lean-import" "$arena_dir/checkers/rocq-lean-import"

echo "Lean Kernel Arena ready at $arena_dir"
echo "Installed checker: checkers/rocq-lean-import.yaml"
