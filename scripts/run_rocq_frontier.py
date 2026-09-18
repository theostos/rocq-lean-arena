#!/usr/bin/env python3
"""Run one reproducible rocq-lean-import frontier experiment."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from typing import Any


PROGRESS_RE = re.compile(r"^line (\d+): (.+)$")
ERROR_RE = re.compile(r"Error at line (\d+)(?: \(for ([^)]+)\))?")
ANOMALY_RE = re.compile(r"^(?:Error:\s*)?Anomaly\b")
ELAPSED_RE = re.compile(
    r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*(.+)"
)
MAX_RSS_RE = re.compile(r"Maximum resident set size \(kbytes\):\s*(\d+)")
TMPDIR_RE = re.compile(r"^Temporary checker directory: (.+)$")
ENTRY_RE = re.compile(r"^#(?:DEF|ABBREV|REGULAR|HINT_OPAQUE|OPAQUE|AX|IND|QUOT)\b")
SKIPPED_RE = re.compile(r"^Skipped [1-9][0-9]*\b")


def run_text(command: list[str], *, cwd: Path | None = None) -> str:
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def exit_status(returncode: int) -> int:
    """Use shell-style statuses without assuming why a signal was delivered."""
    return returncode if returncode >= 0 else 128 - returncode


def guard_shutdown_timeout() -> int:
    """Cover the guard's configured TERM grace, 30s KILL wait, and a margin."""
    try:
        grace = int(os.environ.get("ROCQ_MEMORY_TERM_GRACE_SECONDS", "2"))
    except ValueError:
        grace = 60
    if not 1 <= grace <= 60:
        grace = 60
    return max(40, grace + 35)


def stop_process(process: subprocess.Popen) -> None:
    """Stop our owned session, allowing its guard to reap detached workers.

    The process must have been launched with start_new_session=True. Sending
    TERM only to /usr/bin/time would leave its guard child running. Likewise,
    reaping time alone does not establish that the guard has finished cleanup.
    """
    def signal_group(signum: int) -> bool:
        try:
            os.killpg(process.pid, signum)
        except ProcessLookupError:
            return False
        return True

    signal_group(signal.SIGTERM)
    deadline = time.monotonic() + guard_shutdown_timeout()
    while True:
        process.poll()
        if not signal_group(0):
            break
        if time.monotonic() >= deadline:
            signal_group(signal.SIGKILL)
            break
        time.sleep(0.05)
    process.wait()


def run_guarded(
    guard: Path, command: list[str], *, capture: bool = False
) -> str:
    guarded = [str(guard), *command]
    process = subprocess.Popen(
        guarded, stdout=subprocess.PIPE if capture else None, text=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate()
    except BaseException:
        stop_process(process)
        raise
    if process.returncode:
        raise subprocess.CalledProcessError(exit_status(process.returncode), guarded)
    return (output or "").strip()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(8 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def input_identity(path: Path) -> dict[str, Any]:
    stat = path.stat()
    identity = {
        "path": str(path),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
    }
    # Equal size and mtime do not establish equal contents.
    identity["sha256"] = sha256_file(path)
    return identity


def next_export_entry(path: Path, after_line: int | None) -> dict[str, Any] | None:
    if after_line is None:
        return None
    with path.open("r", encoding="utf-8", errors="replace") as source:
        for line_number, raw in enumerate(source, start=1):
            if line_number > after_line and ENTRY_RE.match(raw):
                return {"line": line_number, "raw": raw.rstrip("\n")}
    return None


def write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8") as output:
        json.dump(value, output, indent=2, sort_keys=True)
        output.write("\n")
    os.replace(temporary, path)


def classify(
    returncode: int, *, saw_timeout: bool, saw_import_error: bool, saw_anomaly: bool,
    saw_skipped: bool = False,
) -> str:
    if returncode == 124 or saw_timeout:
        return "timeout"
    if saw_import_error:
        return "import-error"
    if saw_anomaly:
        return "rocq-anomaly"
    if saw_skipped:
        return "incomplete-import"
    if returncode == 0:
        return "success"
    return "checker-failure"


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="NDJSON or legacy Lean export")
    parser.add_argument(
        "--importer-root",
        type=Path,
        default=repo_root / "_worktrees/rocq-lean-import/generic-cslib-current",
    )
    parser.add_argument("--opam-switch", default="rocq93_clean")
    parser.add_argument("--expected-rocq", default="9.3")
    parser.add_argument("--from-line", type=int)
    parser.add_argument("--until-line", type=int)
    parser.add_argument("--progress-timeout", type=int, default=300)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument(
        "--state",
        type=Path,
        default=repo_root / "_build/frontier/state.json",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=repo_root / "_build/frontier/logs",
    )
    args = parser.parse_args()
    if args.jobs != 1:
        parser.error("--jobs must be 1: concurrent Rocq workers are disabled")
    return args


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    input_path = args.input.resolve()
    importer_root = args.importer_root.resolve()
    run_script = repo_root / "checkers/rocq-lean-import/scripts/run.sh"
    guard = run_script.with_name("run-memory-guarded.sh")

    if not input_path.is_file():
        raise SystemExit(f"Input file not found: {input_path}")
    if not (importer_root / ".git").exists() and not run_text(
        ["git", "-C", str(importer_root), "rev-parse", "--is-inside-work-tree"]
    ) == "true":
        raise SystemExit(f"Importer worktree not found: {importer_root}")
    if (args.from_line is None) != (args.until_line is None):
        raise SystemExit("--from-line and --until-line must be provided together")
    if args.from_line is not None and args.from_line > args.until_line:
        raise SystemExit("--from-line must not exceed --until-line")

    if not args.no_build:
        run_guarded(
            guard,
            [
                "opam",
                "exec",
                f"--switch={args.opam_switch}",
                "--",
                "make",
                "-C",
                str(importer_root),
                f"-j{args.jobs}",
            ],
        )

    importer_commit = run_text(["git", "-C", str(importer_root), "rev-parse", "HEAD"])
    importer_status = run_text(
        ["git", "-C", str(importer_root), "status", "--short", "--untracked-files=no"]
    )
    rocq_bin = os.environ.get("ROCQLKA_ROCQ") or "rocq"
    if os.sep in rocq_bin:
        # Keep relative paths valid from the checker's temporary directory,
        # without collapsing '..' across a possible symlink.
        rocq_bin = os.path.join(os.getcwd(), rocq_bin)
    rocq_command = ["opam", "exec", f"--switch={args.opam_switch}", "--", rocq_bin]
    rocq_version = run_guarded(
        guard, [*rocq_command, "--version"], capture=True,
    ).splitlines()[0]
    if args.expected_rocq not in rocq_version:
        raise SystemExit(
            f"Unexpected Rocq version: {rocq_version!r}; expected {args.expected_rocq!r}"
        )

    old_state: dict[str, Any] = {}
    if args.state.is_file():
        with args.state.open("r", encoding="utf-8") as source:
            old_state = json.load(source)
    identity = input_identity(input_path)

    started_at = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    stamp = time.strftime("%Y%m%d-%H%M%S")
    args.log_dir.mkdir(parents=True, exist_ok=True)
    log_path = args.log_dir / f"frontier-{stamp}-{time.time_ns()}.log"

    environment = os.environ.copy()
    environment.update(
        {
            "ROCQLKA_OPAM_SWITCH": args.opam_switch,
            "ROCQLKA_ROCQ": rocq_bin,
            "ROCQLKA_IMPORTER_ROOT": str(importer_root),
            "ROCQLKA_EXPECT_IMPORTER_COMMIT": importer_commit,
            "ROCQLKA_EXPECT_ROCQ_VERSION": args.expected_rocq,
            "ROCQLKA_PROGRESS_TIMEOUT": str(args.progress_timeout),
            "ROCQLKA_KEEP_TMP": "1",
            "ROCQLKA_LEAN_ERROR_MODE": "Fail",
        }
    )
    if args.from_line is not None:
        environment["ROCQLKA_LEAN_FROM"] = str(args.from_line)
        environment["ROCQLKA_LEAN_UNTIL"] = str(args.until_line)
    else:
        # A full frontier run must not inherit a shell's earlier diagnostic range.
        environment.pop("ROCQLKA_LEAN_FROM", None)
        environment.pop("ROCQLKA_LEAN_UNTIL", None)

    command = ["/usr/bin/time", "-v", str(run_script), str(input_path)]
    last_progress_line: int | None = None
    last_progress_name: str | None = None
    error_line: int | None = None
    error_name: str | None = None
    elapsed_reported: str | None = None
    max_rss_kb: int | None = None
    checker_tmpdir: str | None = None
    saw_timeout = False
    saw_import_error = False
    saw_anomaly = False
    saw_skipped = False
    started = time.monotonic()

    with log_path.open("x", encoding="utf-8") as log:
        process = subprocess.Popen(
            command,
            cwd=repo_root,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            bufsize=1,
            start_new_session=True,
        )
        try:
            assert process.stdout is not None
            for line in process.stdout:
                sys.stdout.write(line)
                sys.stdout.flush()
                log.write(line)
                stripped = line.rstrip("\n")
                if match := PROGRESS_RE.match(stripped):
                    last_progress_line = int(match.group(1))
                    last_progress_name = match.group(2)
                    # Lean names may themselves contain diagnostic words.
                    continue
                if match := ERROR_RE.search(stripped):
                    error_line = int(match.group(1))
                    error_name = match.group(2)
                    saw_import_error = True
                if match := ELAPSED_RE.search(stripped):
                    elapsed_reported = match.group(1)
                if match := MAX_RSS_RE.search(stripped):
                    max_rss_kb = int(match.group(1))
                if match := TMPDIR_RE.match(stripped):
                    checker_tmpdir = match.group(1)
                saw_timeout = saw_timeout or "Timed out after" in stripped
                saw_anomaly = saw_anomaly or bool(ANOMALY_RE.match(stripped))
                saw_skipped = saw_skipped or bool(SKIPPED_RE.match(stripped))
            returncode = exit_status(process.wait())
        except BaseException:
            stop_process(process)
            raise
        finally:
            if process.stdout is not None:
                process.stdout.close()

    wall_seconds = time.monotonic() - started
    result = classify(
        returncode,
        saw_timeout=saw_timeout,
        saw_import_error=saw_import_error,
        saw_anomaly=saw_anomaly,
        saw_skipped=saw_skipped,
    )
    candidate = next_export_entry(input_path, last_progress_line) if result != "success" else None

    run_record = {
        "started_at": started_at,
        "input": identity,
        "result": result,
        "returncode": returncode,
        "wall_seconds": round(wall_seconds, 3),
        "elapsed_reported": elapsed_reported,
        "max_rss_kb": max_rss_kb,
        "from_line": args.from_line,
        "until_line": args.until_line,
        "last_progress_line": last_progress_line,
        "last_progress_name": last_progress_name,
        "error_line": error_line,
        "error_name": error_name,
        "next_export_entry": candidate,
        "checker_tmpdir": checker_tmpdir,
        "log": str(log_path.resolve()),
        "importer": {
            "root": str(importer_root),
            "commit": importer_commit,
            "dirty": bool(importer_status),
        },
        "rocq": {
            "switch": args.opam_switch,
            "command": rocq_command,
            "version": rocq_version,
        },
    }
    history = old_state.get("runs", [])
    if not isinstance(history, list):
        history = []
    history.append(run_record)
    state = {"input": identity, "latest": run_record, "runs": history[-100:]}
    write_json_atomic(args.state, state)
    print(f"Frontier state: {args.state.resolve()}")
    return returncode or int(result != "success")


if __name__ == "__main__":
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    # Raise through the cleanup paths when the frontend itself is stopped.
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    try:
        status = main()
    except subprocess.CalledProcessError as error:
        status = exit_status(error.returncode)
    except KeyboardInterrupt:
        status = 130
    raise SystemExit(status)
