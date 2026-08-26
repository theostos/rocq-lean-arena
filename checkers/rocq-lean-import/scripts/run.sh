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

importer_root="${ROCQLKA_IMPORTER_ROOT:-}"
rocq_compile_args=()
importer_commit="installed"
importer_dirty="unknown"
if [[ -n "$importer_root" ]]; then
  if [[ ! -d "$importer_root/src" ]]; then
    echo "Importer source directory not found: $importer_root/src" >&2
    exit 3
  fi
  importer_root="$(cd "$importer_root" && pwd -P)"
  importer_src="$importer_root/src"
  for artifact in Lean.vo lean_import.cmxs; do
    if [[ ! -f "$importer_src/$artifact" ]]; then
      echo "Importer artifact not found: $importer_src/$artifact" >&2
      echo "Build the selected importer worktree before running the checker." >&2
      exit 3
    fi
  done
  rocq_compile_args=(-I "$importer_src" -Q "$importer_src" LeanImport)
  if git -C "$importer_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    importer_commit="$(git -C "$importer_root" rev-parse HEAD)"
    if [[ -n "$(git -C "$importer_root" status --short --untracked-files=no)" ]]; then
      importer_dirty="true"
    else
      importer_dirty="false"
    fi
  fi
fi

expected_importer="${ROCQLKA_EXPECT_IMPORTER_COMMIT:-}"
if [[ -n "$expected_importer" && "$importer_commit" != "$expected_importer"* ]]; then
  echo "Unexpected importer commit: $importer_commit (expected $expected_importer)" >&2
  exit 3
fi

rocq_version="$("${rocq_cmd[@]}" --version | sed -n '1p')"
expected_rocq="${ROCQLKA_EXPECT_ROCQ_VERSION:-}"
if [[ -n "$expected_rocq" && "$rocq_version" != *"$expected_rocq"* ]]; then
  echo "Unexpected Rocq version: $rocq_version (expected to contain $expected_rocq)" >&2
  exit 3
fi

progress_timeout="${ROCQLKA_PROGRESS_TIMEOUT:-600}"
case "$progress_timeout" in
  0|false|FALSE|no|NO|never|NEVER|off|OFF)
    progress_timeout=0
    ;;
  ''|*[!0-9]*)
    echo "Unsupported ROCQLKA_PROGRESS_TIMEOUT value: $progress_timeout" >&2
    exit 3
    ;;
esac

progress_poll="${ROCQLKA_PROGRESS_POLL:-5}"
case "$progress_poll" in
  ''|*[!0-9]*)
    echo "Unsupported ROCQLKA_PROGRESS_POLL value: $progress_poll" >&2
    exit 3
    ;;
esac
if [[ "$progress_poll" -eq 0 ]]; then
  echo "ROCQLKA_PROGRESS_POLL must be greater than 0" >&2
  exit 3
fi

announce() {
  echo "$*" >&2
  if [[ ! -t 2 && "${ROCQLKA_ANNOUNCE_TTY:-1}" != 0 ]]; then
    printf '%s\n' "$*" 2>/dev/null >/dev/tty || true
  fi
}

tmp_root="${ROCQLKA_TMP_ROOT:-${TMPDIR:-/tmp}}"
mkdir -p "$tmp_root"
tmpdir="$(mktemp -d "$tmp_root/rocq-lean-import.XXXXXX")"
announce "Temporary checker directory: $tmpdir"
announce "Rocq: $rocq_version"
announce "Importer: $importer_commit (dirty: $importer_dirty, root: ${importer_root:-installed})"

python3 - \
  "$tmpdir/provenance.json" \
  "$rocq_version" \
  "${ROCQLKA_OPAM_SWITCH:-}" \
  "$importer_root" \
  "$importer_commit" \
  "$importer_dirty" <<'PY'
import json
import sys

path, rocq_version, opam_switch, importer_root, importer_commit, importer_dirty = sys.argv[1:]
with open(path, "w", encoding="utf-8") as out:
    json.dump(
        {
            "rocq_version": rocq_version,
            "opam_switch": opam_switch or None,
            "importer_root": importer_root or None,
            "importer_commit": importer_commit,
            "importer_dirty": importer_dirty,
        },
        out,
        indent=2,
        sort_keys=True,
    )
    out.write("\n")
PY

keep_tmp="${ROCQLKA_KEEP_TMP:-1}"
cleanup() {
  case "$keep_tmp" in
    0|false|FALSE|no|NO|never|NEVER|off|OFF)
      rm -rf "$tmpdir"
      ;;
    *)
      announce "Keeping temporary checker directory: $tmpdir"
      ;;
  esac
}
trap cleanup EXIT

legacy="$tmpdir/input.lean-export"
adapter_stdout="$tmpdir/adapter.stdout"
adapter_stderr="$tmpdir/adapter.stderr"
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
      python3 "$converter" "$input" "$cache_tmp" >"$adapter_stdout" 2>"$adapter_stderr"
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
    python3 "$converter" "$input" "$legacy" >"$adapter_stdout" 2>"$adapter_stderr"
    adapter_status=$?
    set -e
  fi

  if [[ "${adapter_status:-0}" -eq 10 ]]; then
    cat "$adapter_stdout"
    cat "$adapter_stderr" >&2
    exit 1
  fi
  if [[ "${adapter_status:-0}" -ne 0 ]]; then
    cat "$adapter_stdout"
    cat "$adapter_stderr" >&2
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
lean_from="${ROCQLKA_LEAN_FROM:-}"
lean_until="${ROCQLKA_LEAN_UNTIL:-}"
if [[ -n "$lean_from" && "$lean_from" == *[!0-9]* ]]; then
  echo "ROCQLKA_LEAN_FROM must be a non-negative integer: $lean_from" >&2
  exit 3
fi
if [[ -n "$lean_until" && "$lean_until" == *[!0-9]* ]]; then
  echo "ROCQLKA_LEAN_UNTIL must be a non-negative integer: $lean_until" >&2
  exit 3
fi
if [[ -n "$lean_from" && -z "$lean_until" ]] ||
   [[ -z "$lean_from" && -n "$lean_until" ]]; then
  echo "Set ROCQLKA_LEAN_FROM and ROCQLKA_LEAN_UNTIL together" >&2
  exit 3
fi
if [[ -n "$lean_from" && -n "$lean_until" && "$lean_from" -gt "$lean_until" ]]; then
  echo "ROCQLKA_LEAN_FROM must not exceed ROCQLKA_LEAN_UNTIL" >&2
  exit 3
fi

lean_range=""
if [[ -n "$lean_from" ]]; then
  lean_range=" $lean_from $lean_until"
fi
cat > "$tmpdir/Check.v" <<V
From LeanImport Require Import Lean.
Set Lean Error Mode "$lean_error_mode".
V
if [[ -n "${ROCQLKA_LEAN_LINE_TIMEOUT:-}" ]]; then
  printf 'Set Lean Line Timeout %s.\n' "$ROCQLKA_LEAN_LINE_TIMEOUT" >>"$tmpdir/Check.v"
fi
cat >> "$tmpdir/Check.v" <<V
Lean Import "$quoted_legacy"$lean_range.
V

run_rocq_compile() {
  local stdout="$tmpdir/rocq.stdout"
  local stderr="$tmpdir/rocq.stderr"
  local pid use_setsid last_size size last_progress now

  use_setsid=0
  if command -v setsid >/dev/null 2>&1; then
    use_setsid=1
    setsid "${rocq_cmd[@]}" compile "${rocq_compile_args[@]}" -q "$tmpdir/Check.v" >"$stdout" 2>"$stderr" &
  else
    "${rocq_cmd[@]}" compile "${rocq_compile_args[@]}" -q "$tmpdir/Check.v" >"$stdout" 2>"$stderr" &
  fi
  pid=$!
  last_size=0
  last_progress="$(date +%s)"

  while kill -0 "$pid" 2>/dev/null; do
    sleep "$progress_poll"
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    if [[ -f "$stdout" ]]; then
      size="$(wc -c <"$stdout")"
    else
      size=0
    fi
    now="$(date +%s)"

    if [[ "$size" -ne "$last_size" ]]; then
      last_size="$size"
      last_progress="$now"
    elif [[ "$progress_timeout" -gt 0 && $((now - last_progress)) -ge "$progress_timeout" ]]; then
      {
        printf 'Timed out after %s seconds without rocq stdout progress.\n' "$progress_timeout"
        printf 'Last stdout byte count: %s.\n' "$last_size"
      } >>"$stderr"
      if [[ "$use_setsid" -eq 1 ]]; then
        kill -TERM "-$pid" 2>/dev/null || true
      else
        kill -TERM "$pid" 2>/dev/null || true
      fi
      sleep 2
      if kill -0 "$pid" 2>/dev/null; then
        if [[ "$use_setsid" -eq 1 ]]; then
          kill -KILL "-$pid" 2>/dev/null || true
        else
          kill -KILL "$pid" 2>/dev/null || true
        fi
      fi
      wait "$pid" 2>/dev/null || true
      return 124
    fi
  done

  wait "$pid"
}

set +e
run_rocq_compile
status=$?
set -e

cat "$tmpdir/rocq.stdout"
cat "$tmpdir/rocq.stderr" >&2

if [[ "$status" -eq 0 ]]; then
  exit 0
fi
if [[ "$status" -eq 124 ]]; then
  exit 124
fi

exit 1
