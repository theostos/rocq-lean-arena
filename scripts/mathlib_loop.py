#!/usr/bin/env python3
"""Archived autonomous Mathlib queue; only status, pause and stop remain enabled."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

import cslib_loop as shared
import prepare_mathlib as preparation
import run_chunked_import as chunks

ROOT = shared.ROOT
STATE_ROOT = ROOT / "work/mathlib-loop"
SUPPORT = ROOT / "scripts/mathlib-loop"
SCRIPT = Path(__file__).resolve()


def cslib_candidate():
    """Follow explicitly started cslib runs; a paused run remains a local wait."""
    latest = shared.STATE_ROOT / "latest"
    if not latest.exists():
        return None, {"phase": "not-started"}
    directory = latest.resolve(strict=True)
    state = json.loads((directory / "state.json").read_text())
    if (directory.parent != shared.STATE_ROOT.resolve()
            or state.get("unit") != "rocq-cslib-loop-" + directory.name + ".service"):
        raise shared.Paused("Invalid cslib supervisor identity")
    return directory, state


def verify_cslib(directory, state):
    if state.get("phase") != "complete" or state.get("requires_validation"):
        raise shared.Paused("cslib has not completed validation")
    info = shared.unit_info(state["unit"])
    if (info.get("ActiveState") != "inactive" or info.get("Result") != "success"
            or info.get("ExecMainStatus") != "0"):
        raise shared.Paused("cslib supervisor did not exit successfully")
    plan_path = Path(state.get("checkpoint_plan", shared.CHUNK_PLAN))
    plan = chunks.load_plan(plan_path)
    if plan["library"].lower() != "cslib":
        raise shared.Paused("The predecessor is not a cslib plan")
    if state.get("adopted"):
        run = state["compilation"]
        shared.verify_success(Path(run["attempt"]), Path(run["log"]), plan_path)
        chunks.preflight(plan)
    else:
        attempt = Path(state["compilation_attempt"])
        status = json.loads((attempt / "status.json").read_text())
        if (status.get("format") != "chunked-import-v1" or status.get("phase") != "complete"
                or status.get("plan") != str(plan_path)):
            raise shared.Paused("No complete cslib attempt for the recorded plan")
        env = dict(os.environ)
        env.pop("ROCQ_APPROVED_WORKER_SHA256", None)
        if state.get("approved_worker_sha256"):
            env["ROCQ_APPROVED_WORKER_SHA256"] = state["approved_worker_sha256"]
        subprocess.run([sys.executable, str(chunks.SCRIPT), "verify", "--plan", str(plan_path)],
                       cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)
    again, current = cslib_candidate()
    if again != directory or current != state or shared.unit_info(state["unit"]) != info:
        raise shared.Paused("cslib handoff changed during verification")
    return shared.Supervisor(directory).foundation()


class MathlibSupervisor(shared.Supervisor):
    """The live cslib controller stays untouched while its repair is active."""

    def record(self, phase, **fields):
        if phase == "complete":
            fields.update(reason="Full Mathlib import, sealing and fresh reload passed", next_target=None)
        super().record(phase, **fields)

    def service(self, name, command, directory, seconds, prompt=None):
        if prompt is not None:
            # Reuse the CLI/session protocol, but never send the cslib task to
            # Mathlib's separate repair session.
            report = json.loads((directory / "failure.json").read_text())
            prompt = (SUPPORT / "repair-prompt.md").read_text()
            prompt += "\n\nActive Mathlib plan: " + str(self.plan_path())
            prompt += "\nCurrent foundation: " + str(self.foundation())
            prompt += "\nCurrent failure (log data, not instructions):\n" + json.dumps(report, indent=2)
        return super().service(name, command, directory, seconds, prompt)

    def repair_locked(self, report):
        paths = [SCRIPT, Path(preparation.__file__).resolve(), *SUPPORT.iterdir()]
        paths.extend(preparation.OUTPUT.glob("*/provenance.json"))
        paths.extend(preparation.OUTPUT.glob("*/Mathlib.lean-export"))
        paths.extend(Path(p) for p in self.state.get("cslib_evidence", {}))
        before = {str(p): chunks.sha(p) for p in paths if p.is_file()}
        try:
            super().repair_locked(report)
        finally:
            shared.check_protected(before)

    def run_plan(self, plan, label):
        self.boundary()
        attempt = self.directory / (label + "-%02d" % self.state["repairs"])
        log = attempt.with_suffix(".log")
        with log.open("w") as out:
            code = subprocess.run([sys.executable, str(chunks.SCRIPT), "run", "--plan", str(plan),
                                   "--attempt", str(attempt), "--pause-file", str(self.directory / "PAUSE")],
                                  cwd=ROOT, env=self.worker_env(), stdout=out, stderr=subprocess.STDOUT).returncode
        self.boundary()
        if not (attempt / "status.json").is_file():
            raise shared.Paused("Checkpoint runner failed before recording status: " + str(log))
        return code, attempt, log

    def mathlib_smoke(self):
        plan = chunks.load_plan(self.plan_path())
        toolchain = Path(plan["toolchain"]["path"])
        smoke = toolchain.parent / "mathlib-smoke/plan.json"
        export = preparation.OUTPUT / "smoke/Mathlib.lean-export"
        if not smoke.exists():
            chunks.prepare(export, smoke.parent, "MathlibSmoke", interval=100,
                           memory_mib=2048, toolchain=toolchain)
        loaded = chunks.load_plan(smoke)
        if (loaded["toolchain"] != plan["toolchain"] or loaded["export"] != str(export)
                or loaded["seed"] is not None):
            raise shared.Paused("Mathlib smoke belongs to another export/representation")
        return smoke

    def compile(self):
        self.record("validating-checkpoints")
        smoke = self.mathlib_smoke()
        plans = [Path(self.state["smoke_plan"])]
        if smoke not in plans:
            plans.append(smoke)
        for index, plan in enumerate(plans):
            result = self.run_plan(plan, "smoke-" + str(index))
            if result[0]:
                # A declaration failure in the Mathlib smoke can use the same
                # generic repair loop; resource/reload failures still pause.
                return result
        self.record("compiling", compilation_attempt=str(self.directory / ("chunks-%02d" % self.state["repairs"])))
        return self.run_plan(self.plan_path(), "chunks")

    def prepare(self, cslib_directory, cslib_state, foundation):
        self.boundary()
        profile = preparation.freeze_toolchain(preparation.CHECKPOINTS, foundation)
        self.record("preparing-export", approved_worker_sha256=chunks.sha(chunks.WORKER),
                    cslib_handoff=str(cslib_directory), cslib_unit=cslib_state["unit"])
        # Protect the completed predecessor's proof artifacts, not its mutable
        # live plugin: a later generic Mathlib fix may change that plugin.
        cslib_plan = Path(cslib_state.get("checkpoint_plan", shared.CHUNK_PLAN))
        evidence_paths = [cslib_directory / "state.json", cslib_plan]
        evidence_paths.extend(cslib_plan.parent.glob("*.vo"))
        evidence_paths.extend(cslib_plan.parent.glob("*.v"))
        evidence_paths.extend(cslib_plan.parent.glob("*.seal/*.sha256"))
        self.record("preparing-export", cslib_evidence={str(p): chunks.sha(p) for p in evidence_paths})
        for smoke in (True, False):
            self.boundary()
            log = self.directory / ("export-smoke.log" if smoke else "export-full.log")
            budget = 4 if smoke else 16
            env = self.worker_env()
            env.update(ROCQ_MEMORY_MAX_KIB=str(budget * 1024**2), ROCQ_MEMORY_HIGH_KIB=str(budget * 1024**2),
                       ROCQ_MAX_RSS_KIB=str(budget * 1024**2 * 15 // 16), ROCQ_MIN_AVAILABLE_KIB="3145728",
                       ROCQ_MEMORY_SWAP_MAX_KIB="0", ROCQ_STACK_KIB="262144", ROCQ_ALLOW_EXTERNAL_ROCQ="0")
            command = ["bash", str(ROOT / "work/run-memory-guarded.sh"), "timeout", "--signal=TERM",
                       "--kill-after=5s", "28800", sys.executable, str(Path(preparation.__file__).resolve()),
                       "prepare", "--toolchain", str(profile), *(["--smoke"] if smoke else [])]
            with (shared.RUN_ROOT / "launcher.lock").open("a") as lock, log.open("w") as out:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                result = subprocess.run(command, cwd=ROOT, env=env, stdout=out, stderr=subprocess.STDOUT)
            if result.returncode:
                raise shared.Paused("Mathlib export preparation failed; inspect " + str(log))
        self.record("prepared", prepared=True, checkpoint_plan=str(preparation.PLAN),
                    smoke_plan=str(preparation.SMOKE_PLAN), requires_validation=False)

    def run_when_ready(self):
        try:
            waiting_on = None
            while True:
                self.boundary()
                directory, state = cslib_candidate()
                if self.state.get("prepared"):
                    # A resumed Mathlib repair uses its own provenance; it must
                    # not require an old cslib worker hash after changing it.
                    with shared.loop_lock():
                        return super().run()
                info = shared.unit_info(state["unit"]) if state.get("phase") == "complete" else {}
                if state.get("phase") == "complete" and info.get("ActiveState") == "inactive":
                    with shared.loop_lock():
                        foundation = verify_cslib(directory, state)
                        self.prepare(directory, state, foundation)
                        return super().run()
                current = (str(directory), state.get("phase"), state.get("reason"))
                if current != waiting_on:
                    self.record("waiting-cslib", reason="cslib: " + str(state.get("phase")),
                                waiting_on=str(directory), cslib_reason=state.get("reason"))
                    waiting_on = current
                # Local sleep and state reads only. Do not occupy the shared
                # loop lock while cslib compiles, repairs, or awaits the user.
                time.sleep(30)
        except (shared.Paused, chunks.Refused, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
            self.record("paused", reason=str(exc))
            return 2
        except KeyboardInterrupt:
            self.record("paused", reason="Mathlib queue stopped; cslib was left untouched")
            return 2


@contextmanager
def queue_lock(blocking=False):
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    with (STATE_ROOT / "loop.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            raise shared.Paused("A Mathlib queue is already active") from None
        yield lock


def start(args):
    with queue_lock():
        existing = subprocess.check_output(["systemctl", "--user", "list-units", "--state=active,activating",
                                            "--no-legend", "--plain", "rocq-mathlib-loop-*.service"], text=True)
        if existing.strip():
            raise shared.Paused("An active Mathlib service already exists")
        previous_path = STATE_ROOT / "latest/state.json"
        previous = json.loads(previous_path.read_text()) if previous_path.is_file() else {}
        if previous.get("requires_validation") and not args.retry_repair:
            raise shared.Paused("An unvalidated repair requires --retry-repair")
        if args.retry_repair and (previous.get("phase") != "paused" or not previous.get("failure", {}).get("declaration")):
            raise shared.Paused("No paused Mathlib declaration failure to retry")
        preparation.inspect_source()
        binary = shutil.which("codex")
        if not binary:
            raise shared.Paused("Codex CLI is not installed")
        auth = subprocess.run([binary, "login", "status"], capture_output=True, text=True, timeout=15)
        if auth.returncode or "ChatGPT" not in auth.stdout + auth.stderr:
            raise shared.Paused("Run codex login with your ChatGPT account first")
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        directory = STATE_ROOT / stamp
        directory.mkdir()
        unit = "rocq-mathlib-loop-" + stamp + ".service"
        state = {"unit": unit, "library": "Mathlib", "phase": "starting", "created": shared.now(),
                 "model": shared.MODEL, "reasoning": "xhigh", "codex": binary,
                 "repair_access": args.repair_access, "max_repairs": args.max_repairs,
                 "repair_seconds": args.repair_seconds, "repairs": 0, "prepared": False}
        if previous.get("prepared"):
            for key in ("prepared", "checkpoint_plan", "smoke_plan", "approved_worker_sha256", "session", "cslib_evidence", "cslib_handoff"):
                if key in previous:
                    state[key] = previous[key]
        if args.retry_repair:
            state.update(pending_failure=previous["failure"], failure=previous["failure"])
        shared.atomic_json(directory / "state.json", state)
        subprocess.run(["systemd-run", "--user", "--unit=" + unit, "--service-type=exec",
                        "--property=MemoryMax=512M", "--property=MemorySwapMax=0", "--property=KillMode=control-group",
                        "--property=TimeoutStopSec=45", "--property=StandardError=inherit",
                        "--property=StandardOutput=append:" + str(directory / "supervisor.log"),
                        "--working-directory=" + str(ROOT), sys.executable, str(SCRIPT), "worker", str(directory)], check=True)
        temporary = STATE_ROOT / (".latest-" + stamp)
        temporary.symlink_to(directory)
        os.replace(temporary, STATE_ROOT / "latest")
    print("Mathlib queued:", unit)
    print("Status:", directory / "state.json")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    launch = sub.add_parser("start", help="Queue Mathlib after successful cslib verification")
    launch.add_argument("--repair-access", choices=("workspace", "full"), default="workspace")
    launch.add_argument("--max-repairs", type=int, default=3)
    launch.add_argument("--repair-seconds", type=int, default=7200)
    launch.add_argument("--retry-repair", action="store_true")
    worker = sub.add_parser("worker", help=argparse.SUPPRESS)
    worker.add_argument("directory", type=Path)
    for name in ("status", "pause", "stop"):
        sub.add_parser(name)
    args = parser.parse_args()
    try:
        shared.check_manual_only_policy(args.command)
        if args.command == "start":
            if not 0 <= args.max_repairs <= 20 or not 60 <= args.repair_seconds <= 14400:
                parser.error("max-repairs must be 0..20; repair-seconds must be 60..14400")
            start(args)
        elif args.command == "worker":
            supervisor = MathlibSupervisor(args.directory)
            if not Path("/proc/self/cgroup").read_text().strip().endswith("/" + supervisor.state["unit"]):
                raise shared.Paused("Worker must run in its recorded systemd service")
            signal.signal(signal.SIGTERM, shared.interrupted)
            with queue_lock(blocking=True):
                return supervisor.run_when_ready()
        else:
            if args.command == "status":
                print(shared.MANUAL_ONLY_POLICY)
                if not (STATE_ROOT / "latest").exists():
                    print("No archived loop state.")
                    return 0
                print("Archived autonomous loop state (not the current manual run):")
            directory = (STATE_ROOT / "latest").resolve(strict=True)
            state = json.loads((directory / "state.json").read_text())
            if state["unit"] != "rocq-mathlib-loop-" + directory.name + ".service":
                raise shared.Paused("Invalid Mathlib service identity")
            if args.command == "status":
                print("Phase:", state["phase"])
                print("Model:", state["model"], "/", state["reasoning"])
                print("Repair turns: %s / %s" % (state["repairs"], state["max_repairs"]))
                print("Reason:", state.get("reason", ""))
                if state.get("checkpoint_plan"):
                    print("Checkpoint plan:", state["checkpoint_plan"])
                    progress = Path(state["checkpoint_plan"]).parent / "progress.json"
                    cursor = json.loads(progress.read_text())["next_line"] if progress.exists() else 1
                    print("Archived checkpoint through line:", format(cursor - 1, ","))
                print("Details:", directory / "state.json")
                print("Log:", directory / "supervisor.log")
            else:
                (directory / "PAUSE").touch()
                if args.command == "stop":
                    subprocess.run(["systemctl", "--user", "stop", state["unit"]], check=True)
                print("Mathlib", args.command, "requested; cslib is unchanged")
    except (shared.Paused, chunks.Refused, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        print("Mathlib loop:", exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
