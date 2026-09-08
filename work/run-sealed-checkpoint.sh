#!/usr/bin/env bash
# Reuse an atomic checkpoint only with matching producer inputs and artifact.
set -Eeuo pipefail
(( $# >= 3 )) && [[ $1 == *.v && $2 == -- ]] || {
  echo 'Usage: run-sealed-checkpoint.sh SOURCE.v -- ROCQ-COMMAND [ARG ...]' >&2
  exit 64
}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_file=$(realpath -e -- "$1")
checkpoint=${source_file%.v}.vo
seal=${source_file%.v}.seal
input_manifest=${ROCQ_CHECKPOINT_INPUTS_FILE:?Set ROCQ_CHECKPOINT_INPUTS_FILE}
[[ $input_manifest == /* && -s $input_manifest ]] || exit 64
shift 2
exec 7>"${source_file%.v}.seal.lock"
flock -n 7 || { echo 'Checkpoint sealing already in progress' >&2; exit 75; }
if [[ -e $checkpoint || -e $seal ]]; then
  [[ -s $checkpoint && -d $seal ]] || {
    echo "Incomplete checkpoint/seal pair: $checkpoint; refusing reuse or overwrite." >&2
    exit 65
  }
  sha256sum --check --strict "$seal/inputs.sha256"
  sha256sum --check --strict "$seal/artifact.sha256"
  sha256sum --check --strict "$input_manifest"
  echo "Reusing verified checkpoint: $checkpoint"
  exit 0
fi
seal_stage=$(mktemp -d -- "${source_file%.v}.seal.stage.XXXXXXXX")
trap 'rm -rf -- "$seal_stage"' EXIT
cp -- "$input_manifest" "$seal_stage/inputs.sha256"
sha256sum -- "$source_file" >> "$seal_stage/inputs.sha256"
sha256sum --check --strict "$seal_stage/inputs.sha256"
bash "$script_dir/run-checkpoint-atomic.sh" "$source_file" -- "$@"
sha256sum --check --strict "$seal_stage/inputs.sha256"
sha256sum -- "$checkpoint" > "$seal_stage/artifact.sha256"
mv -T -- "$seal_stage" "$seal"
trap - EXIT
echo "Sealed checkpoint: $checkpoint"
