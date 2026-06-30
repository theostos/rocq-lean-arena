#!/usr/bin/env bash
set -euo pipefail

input="${1:-${IN:-}}"
if [[ -z "$input" ]]; then
  echo "No input path supplied. Pass a path or set IN." >&2
  exit 3
fi

if [[ ! -f "$input" ]]; then
  echo "Input file not found: $input" >&2
  exit 3
fi

rocq_bin="${ROCQLKA_ROCQ:-rocq}"
rocq_cmd=("$rocq_bin")
if [[ -n "${ROCQLKA_OPAM_SWITCH:-}" ]]; then
  rocq_cmd=(opam exec --switch="${ROCQLKA_OPAM_SWITCH}" -- "$rocq_bin")
fi

tmpdir="$(mktemp -d)"
cleanup() {
  if [[ -z "${ROCQLKA_KEEP_TMP:-}" ]]; then
    rm -rf "$tmpdir"
  else
    echo "Keeping temporary checker directory: $tmpdir" >&2
  fi
}
trap cleanup EXIT

legacy="$tmpdir/input.lean-export"
first_nonempty="$(sed -n '/[^[:space:]]/{p;q;}' "$input")"

if [[ "$first_nonempty" == \{* ]]; then
  converter="$(dirname "$0")/ndjson_to_lean_export.py"
  use_cache=0
  cache_mode="${ROCQLKA_LEGACY_CACHE:-auto}"
  case "$cache_mode" in
    1|true|TRUE|yes|YES|always|ALWAYS|on|ON)
      use_cache=1
      ;;
    0|false|FALSE|no|NO|never|NEVER|off|OFF)
      use_cache=0
      ;;
    auto|AUTO|"")
      threshold="${ROCQLKA_NDJSON_STREAM_THRESHOLD:-536870912}"
      input_size="$(wc -c <"$input")"
      if [[ "$input" == *.ndjson && "$input_size" -ge "$threshold" ]]; then
        use_cache=1
      fi
      ;;
    *)
      echo "Unsupported ROCQLKA_LEGACY_CACHE value: $cache_mode" >&2
      exit 3
      ;;
  esac

  if [[ "$use_cache" -eq 1 ]]; then
    cache="${ROCQLKA_LEGACY_CACHE_FILE:-}"
    if [[ -z "$cache" ]]; then
      if [[ "$input" == *.ndjson ]]; then
        cache="${input%.ndjson}.lean-export"
      else
        cache="$input.lean-export"
      fi
    fi
    if [[ -f "$cache" && "$cache" -nt "$input" && "$cache" -nt "$converter" ]]; then
      echo "Using cached legacy export: $cache" >&2
      legacy="$cache"
    else
      mkdir -p "$(dirname "$cache")"
      cache_tmp="$cache.tmp.$$"
      set +e
      python3 "$converter" "$input" "$cache_tmp"
      adapter_status=$?
      set -e
      if [[ "$adapter_status" -eq 0 ]]; then
        mv "$cache_tmp" "$cache"
        legacy="$cache"
      else
        rm -f "$cache_tmp"
      fi
    fi
  else
    set +e
    python3 "$converter" "$input" "$legacy"
    adapter_status=$?
    set -e
  fi

  if [[ "${adapter_status:-0}" -eq 10 ]]; then
    exit 1
  fi
  if [[ "${adapter_status:-0}" -ne 0 ]]; then
    echo "Declining: unsupported NDJSON export for rocq-lean-import adapter." >&2
    exit 2
  fi
elif [[ -f "${input%.ndjson}.lean-export" && "$input" == *.ndjson ]]; then
  legacy="${input%.ndjson}.lean-export"
else
  legacy="$input"
fi

quote_rocq_string() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

quoted_legacy="$(quote_rocq_string "$legacy")"
lean_error_mode="${ROCQLKA_LEAN_ERROR_MODE:-Fail}"
cat > "$tmpdir/Check.v" <<V
From LeanImport Require Import Lean.
Set Lean Error Mode "$lean_error_mode".
V
if [[ -n "${ROCQLKA_LEAN_LINE_TIMEOUT:-}" ]]; then
  printf 'Set Lean Line Timeout %s.\n' "$ROCQLKA_LEAN_LINE_TIMEOUT" >>"$tmpdir/Check.v"
fi
cat >> "$tmpdir/Check.v" <<V
Lean Import "$quoted_legacy".
V

set +e
"${rocq_cmd[@]}" compile -q "$tmpdir/Check.v" >"$tmpdir/rocq.stdout" 2>"$tmpdir/rocq.stderr"
status=$?
set -e

cat "$tmpdir/rocq.stdout"
cat "$tmpdir/rocq.stderr" >&2

if [[ "$status" -eq 0 ]]; then
  exit 0
fi

exit 1
