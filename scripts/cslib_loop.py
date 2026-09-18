#!/usr/bin/env python3
"""Archived autonomous cslib loop; only status, pause and stop remain enabled."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import checkpoint_generation as generations
import run_chunked_import as chunks


ROOT = Path(__file__).resolve().parents[1]
SUPPORT = ROOT / "scripts/cslib-loop"
STATE_ROOT = ROOT / "work/cslib-loop"
RUN_ROOT = ROOT / "work/cslib-full-fresh/runs/cslib-unit-fix"
LAUNCHER = ROOT / "work/uint32-not-repro/resume-cslib.sh"
CHUNK_RUNNER = ROOT / "scripts/run_chunked_import.py"
CHUNK_PLAN = ROOT / "work/library-checkpoints/cslib/plan.json"
SMOKE_PLAN = ROOT / "work/library-checkpoints/smoke/plan.json"
MODEL = "gpt-6-astra"
STAGES = ("Prefix15M", "Reload15M", "Complete15M", "ReloadComplete15M")
DECLARATION = re.compile(r"Error at line (\d+) \(for (.*?)\):")
UNIT = re.compile(r"rocq-cslib-15m-(\d+T\d+)\.service")
MANUAL_ONLY_POLICY = (
    "Autonomy disabled: manual runs start at line 1, without checkpoints or automatic repairs. "
    "Use python3 scripts/run_cslib_from_start.py."
)


class Paused(Exception):
    pass


def check_manual_only_policy(command):
    if command in ("start", "worker"):
        raise Paused(MANUAL_ONLY_POLICY)


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def atomic_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        json.dump(value, f, indent=2)
        f.write("\n")
        temp = f.name
    os.replace(temp, path)


def tail(path, size=4000):
    if not path.is_file():
        return ""
    with path.open("rb") as f:
        f.seek(max(0, path.stat().st_size - size))
        return f.read(size).decode("utf-8", errors="replace")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def unit_info(unit):
    fields = ("LoadState", "ActiveState", "InvocationID", "ExecMainCode",
              "ExecMainStatus", "ExecStart", "Result")
    result = subprocess.run(["systemctl", "--user", "show", unit,
                             *["--property=" + p for p in fields]],
                            capture_output=True, text=True, timeout=15, check=True)
    return dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)


def adopted_run(unit):
    match = UNIT.fullmatch(unit)
    if not match:
        raise Paused("Not a recognized full-pass service: " + unit)
    info = unit_info(unit)
    if (info.get("LoadState") != "loaded" or not info.get("InvocationID")
            or str(LAUNCHER) not in info.get("ExecStart", "")
            or "--checkpoint-only" in info.get("ExecStart", "")):
        raise Paused("Cannot identify a full-pass service safely: " + unit)
    log = LAUNCHER.parent / ("resume." + match[1] + ".service.log")
    # Associate this invocation with its own attempt, never a moving `latest` link.
    with log.open(errors="replace") as f:
        attempt = next((Path(line[6:].strip()) for line in f if line.startswith("Logs: ")), None)
    if (attempt is None or attempt.resolve().parent != RUN_ROOT.resolve()
            or not attempt.name.startswith("attempt.")):
        raise Paused("Cannot associate the service with a checkpoint attempt")
    return {"unit": unit, "invocation": info["InvocationID"],
            "attempt": str(attempt.resolve()), "log": str(log)}


def wait_for_unit(adopted, paused, interval=15):
    """Only local systemd queries and sleep: no Codex process or model request."""
    while True:
        if paused():
            raise Paused("Pause requested; the adopted compilation was left running")
        info = unit_info(adopted["unit"])
        if (info.get("LoadState") != "loaded"
                or info.get("InvocationID") != adopted["invocation"]):
            raise Paused("Adopted service disappeared or changed invocation")
        if info.get("ActiveState") in ("inactive", "failed"):
            if info.get("ExecMainCode") != "1" or info.get("Result") not in ("success", "exit-code"):
                raise Paused("Compilation was stopped, signalled, or killed; no automatic repair")
            return int(info["ExecMainStatus"])
        time.sleep(interval)


def failure_report(attempt, log, code):
    stage = None
    chunk_status = None
    if (attempt / "status.json").exists():
        chunk_status = json.loads((attempt / "status.json").read_text())
        if chunk_status.get("format") != "chunked-import-v1":
            raise Paused("Unknown chunked-run status format")
    with log.open(errors="replace") as f:
        for line in f:
            if line.strip() in ["Starting " + s for s in STAGES]:
                stage = line.strip()[9:]
    if chunk_status:
        stage = chunk_status.get("module")
        if stage and not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", stage):
            raise Paused("Invalid checkpoint module name")
    report = {"exit_code": code, "attempt": str(attempt), "stage": stage,
              "declaration": None, "line": None, "error_start": ""}
    if chunk_status:
        report["checkpoint_phase"] = chunk_status["phase"]
        report["plan"] = chunk_status["plan"]
    if stage:
        run_log = attempt / (stage + ".run.log")
        if run_log.is_file():
            # A giant type error can put the declaration well outside `tail`.
            with run_log.open(errors="replace") as f:
                for line in f:
                    match = DECLARATION.search(line)
                    if match:
                        report.update(line=int(match[1]), declaration=match[2],
                                      error_start=line[:1000] + f.read(5000))
                        break
        report["error_end"] = tail(run_log)
        report["guard_end"] = tail(attempt / (stage + ".guard.log"), 2000)
    report["launcher_end"] = tail(log, 2000)
    return report


def verify_success(attempt, log, plan_path=None):
    plan_path = plan_path or CHUNK_PLAN
    if (attempt / "status.json").exists():
        state = json.loads((attempt / "status.json").read_text())
        if (state.get("format") != "chunked-import-v1" or state.get("phase") != "complete"
                or state.get("plan") != str(plan_path)):
            raise Paused("Chunked continuation did not complete the expected cslib plan")
        subprocess.run([sys.executable, str(CHUNK_RUNNER), "verify", "--plan", str(plan_path)],
                       cwd=ROOT, check=True)
        return
    output = log.read_text(errors="replace")
    if not all("Passed " + s + "\n" in output for s in STAGES):
        raise Paused("Zero exit without all four completed stages; not full success")
    manifest = attempt / "artifacts.sha256"
    expected = {str(RUN_ROOT / (s + ".vo")) for s in STAGES[2:]}
    entries = manifest.read_text().splitlines()
    if len(entries) != 2 or {line.split(maxsplit=1)[1] for line in entries} != expected:
        raise Paused("Missing or unexpected full-pass artifact manifest")
    subprocess.run(["sha256sum", "--check", "--strict", str(manifest)],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    if not (RUN_ROOT / "Complete15M.seal").is_dir():
        raise Paused("Full checkpoint has no seal")


def protected_inputs():
    """Do not let a repair silently weaken checking or rewrite historical evidence."""
    paths = [Path(__file__).resolve(), Path(generations.__file__).resolve(),
             *SUPPORT.iterdir(), *generations.regression_inputs(), LAUNCHER, CHUNK_RUNNER,
             chunks.FOUNDATION / "Lean.vo", chunks.FOUNDATION / "Lean.v",
             ROOT / "work/run-memory-guarded.sh", ROOT / "work/run-checkpoint-atomic.sh",
             ROOT / "work/run-sealed-checkpoint.sh",
             ROOT / "work/lrat-restore-repro/check-prefix15m.sh",
             ROOT / "work/lrat-restore-repro/check-prefix15m-load.sh",
             ROOT / "work/uint32-shift-repro/run-regressions.sh"]
    for name in ("Prefix", "Prefix15M"):
        paths.extend([RUN_ROOT / (name + suffix) for suffix in (".vo", ".v")])
    paths.extend(RUN_ROOT / (stage + ".v") for stage in STAGES[1:])
    paths.extend(RUN_ROOT / name for name in ("inputs.sha256", "prefix.sha256"))
    paths.extend((RUN_ROOT / "Prefix15M.seal").glob("*"))
    for plan in (CHUNK_PLAN, SMOKE_PLAN):
        paths.append(plan)
        paths.extend(plan.parent.glob("*.v"))
        paths.extend(plan.parent.glob("*.vo"))
        paths.extend(plan.parent.glob("*.seal/*.sha256"))
    return {str(p): digest(p) for p in paths if p.is_file()}


def check_protected(before):
    for name, original in before.items():
        if not Path(name).is_file() or digest(Path(name)) != original:
            raise Paused("Protected input changed; refusing continuation: " + name)


def codex_command(binary, session, output, access="workspace"):
    # Both initial and resumed turns explicitly select Astra. Never use --last.
    sandbox = {"workspace": "workspace-write", "full": "danger-full-access"}[access]
    cmd = [binary, "-c", 'approval_policy="never"',
           "-c", 'sandbox_mode="' + sandbox + '"',
           "-c", "sandbox_workspace_write.network_access=true",
           "-c", 'shell_environment_policy.inherit="all"',
           "-c", 'model_reasoning_effort="xhigh"', "exec"]
    if session:
        cmd += ["resume", session]
    cmd += ["--model", MODEL, "--json", "--output-schema", str(SUPPORT / "result.schema.json"),
            "--output-last-message", str(output), "-"]
    return cmd


def read_codex_result(directory):
    session, usage = None, []
    with (directory / "events.jsonl").open(errors="replace") as f:
        for line in f:
            event = json.loads(line)
            if event.get("type") == "thread.started":
                session = event["thread_id"]
            if event.get("type") == "turn.completed":
                usage.append(event.get("usage", {}))
    if not session or not usage:
        raise Paused("Codex did not record a completed turn and a dedicated session")
    result = json.loads((directory / "result.json").read_text())
    if (result.get("status") not in ("ready", "blocked")
            or not isinstance(result.get("summary"), str)
            or not isinstance(result.get("tests"), list)
            or not all(isinstance(t, str) for t in result["tests"])
            or result.get("checkpoint_action") not in ("reuse", "restart")
            or not isinstance(result.get("foundation"), str)):
        raise Paused("Malformed Codex repair result")
    if result["status"] == "ready" and not result["tests"]:
        raise Paused("Codex reported ready without test evidence")
    return session, usage, result


class Supervisor:
    def __init__(self, directory):
        self.directory = directory
        self.state = json.loads((directory / "state.json").read_text())

    def record(self, phase, **fields):
        self.state.update(phase=phase, updated=now(), **fields)
        atomic_json(self.directory / "state.json", self.state)
        print(now(), phase, fields.get("reason", ""), flush=True)

    def pause_requested(self):
        return (self.directory / "PAUSE").exists()

    def boundary(self):
        if self.pause_requested():
            raise Paused("Pause requested; no further work launched")

    def plan_path(self):
        return Path(self.state.get("checkpoint_plan", CHUNK_PLAN))

    def foundation(self):
        plan = json.loads(self.plan_path().read_text())
        return (Path(chunks.generation_toolchain(plan)["foundation"]) if plan.get("toolchain")
                else chunks.FOUNDATION / "Lean.vo")

    def worker_env(self):
        env = {**os.environ, "ROCQ_MEMORY_OWNER_SERVICE": self.state["unit"]}
        env.pop("ROCQ_APPROVED_WORKER_SHA256", None)
        if self.state.get("approved_worker_sha256"):
            env["ROCQ_APPROVED_WORKER_SHA256"] = self.state["approved_worker_sha256"]
        return env

    def service(self, name, command, directory, seconds, prompt=None):
        """A bounded child service; its guarded scopes die with it on cancellation."""
        unit = self.state["unit"].removesuffix(".service") + "-" + name + ".service"
        # systemd does not inherit the environment of its command-line client.
        # Replace any manager-inherited approval with this supervisor's pin.
        approved = self.state.get("approved_worker_sha256")
        worker_pin = ["ROCQ_APPROVED_WORKER_SHA256=" + approved] if approved else []
        command = ["systemd-run", "--user", "--wait", "--pipe", "--collect",
                   "--unit=" + unit, "--service-type=exec",
                   "--property=BindsTo=" + self.state["unit"],
                   "--property=After=" + self.state["unit"],
                   "--property=RuntimeMaxSec=" + str(seconds),
                   "--property=TimeoutStopSec=45", "--property=KillMode=control-group",
                   "--property=MemoryMax=2G", "--property=MemorySwapMax=0",
                   "--working-directory=" + str(ROOT), "/usr/bin/env",
                   "-u", "OPENAI_API_KEY", "-u", "CODEX_API_KEY", "-u", "CODEX_THREAD_ID",
                   "-u", "ROCQ_APPROVED_WORKER_SHA256",
                   "ROCQ_MEMORY_OWNER_SERVICE=" + unit, *worker_pin, *command]
        self.record(self.state["phase"], child_unit=unit)
        with (directory / "events.jsonl").open("w") as out, (directory / "service.log").open("w") as err:
            return subprocess.run(command, cwd=ROOT, input=prompt, text=True,
                                  stdout=out, stderr=err, env=self.worker_env()).returncode

    def compile(self):
        adopted = self.state.pop("adopt", None)
        if adopted:
            self.record("compiling", compilation=adopted, adopted=True)
            code = wait_for_unit(adopted, self.pause_requested)
            return code, Path(adopted["attempt"]), Path(adopted["log"])
        self.boundary()
        log = self.directory / ("compile-%02d.log" % self.state["repairs"])
        env = self.worker_env()
        plan_path = self.plan_path()
        smoke_plan = Path(self.state.get("smoke_plan", SMOKE_PLAN))
        # The first real chunk/save/unpack/reload test waits for the existing
        # full pass to exit. It must never introduce a second Rocq worker.
        self.record("validating-checkpoints", adopted=False)
        smoke_log = self.directory / ("chunk-smoke-%02d.log" % self.state["repairs"])
        smoke_attempt = self.directory / ("chunk-smoke-%02d" % self.state["repairs"])
        with smoke_log.open("w") as f:
            code = subprocess.run([sys.executable, str(CHUNK_RUNNER), "run", "--plan", str(smoke_plan),
                                   "--attempt", str(smoke_attempt), "--pause-file", str(self.directory / "PAUSE")], cwd=ROOT, env=env,
                                  stdout=f, stderr=subprocess.STDOUT).returncode
        self.boundary()
        if code:
            raise Paused("Chunked checkpoint smoke test failed; inspect " + str(smoke_log))
        attempt = self.directory / ("chunks-%02d" % self.state["repairs"])
        self.record("compiling", adopted=False, compilation_log=str(log),
                    checkpoint_plan=str(plan_path), compilation_attempt=str(attempt))
        temporary_link = RUN_ROOT / (".latest-" + self.directory.name)
        temporary_link.symlink_to(attempt)
        os.replace(temporary_link, RUN_ROOT / "latest")
        with log.open("w") as f:
            code = subprocess.run([sys.executable, str(CHUNK_RUNNER), "run", "--plan", str(plan_path),
                                   "--attempt", str(attempt), "--pause-file", str(self.directory / "PAUSE")], cwd=ROOT, env=env,
                                  stdout=f, stderr=subprocess.STDOUT).returncode
        if not (attempt / "status.json").is_file():
            raise Paused("Chunk runner failed before recording its status: " + str(log))
        return code, attempt, log

    def run(self):
        try:
            validation = self.state.pop("pending_validation", None)
            if validation:
                self.boundary()
                self.retry_validation(validation)
            pending = self.state.pop("pending_failure", None)
            if pending:
                self.boundary()
                if self.state["repairs"] >= self.state["max_repairs"]:
                    raise Paused("Repair limit reached")
                self.state.setdefault("failures", {})[pending["declaration"]] = 1
                self.repair(pending)
            while True:
                self.boundary()
                code, attempt, log = self.compile()
                self.boundary()
                if code == 0:
                    with_worker = self.worker_env().get("ROCQ_APPROVED_WORKER_SHA256")
                    if with_worker:
                        # Verification is a local child too, with the approved worker.
                        subprocess.run([sys.executable, str(CHUNK_RUNNER), "verify", "--plan", str(self.plan_path())],
                                       cwd=ROOT, env=self.worker_env(), check=True)
                    else:
                        verify_success(attempt, log, self.plan_path())
                    self.record("complete", reason="Full continuation, save and fresh reload passed",
                                next_target={"library": "Mathlib", "status": "ready for export preparation; not started"})
                    return 0
                report = failure_report(attempt, log, code)
                self.record("failed", failure=report)
                # Resource/cancellation/checkpoint errors must not trigger speculative repairs.
                is_import = report["stage"] == "Complete15M" or report.get("checkpoint_phase") == "importing"
                if code != 1 or not is_import or not report["declaration"]:
                    raise Paused("Not a declaration-checking failure; inspect the run logs")
                key = report["declaration"]
                seen = self.state.setdefault("failures", {})
                seen[key] = seen.get(key, 0) + 1
                if seen[key] >= 2:
                    raise Paused("Same declaration failed again after repair: " + key)
                if self.state["repairs"] >= self.state["max_repairs"]:
                    raise Paused("Repair limit reached")
                self.repair(report)
        except (Paused, chunks.Refused, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
            self.record("paused", reason=str(exc))
            return 2
        except KeyboardInterrupt:
            self.record("paused", reason="Supervisor stopped; inspect logs before restarting")
            return 2

    @contextmanager
    def idle_toolchain(self):
        # Prevent a manual full-pass launcher from racing edits to the toolchain.
        with (RUN_ROOT / "launcher.lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise Paused("A full-pass launcher is still active; no repair started") from None
            workers = subprocess.check_output(["ps", "-u", str(os.getuid()), "-o", "comm="], text=True)
            if any(re.match(r"(?:rocqworker|coqc(?:\.|$))", name) for name in workers.splitlines()):
                raise Paused("A Rocq worker is still active; no repair started")
            yield

    def repair(self, report):
        with self.idle_toolchain():
            self.repair_locked(report)

    def retry_validation(self, handoff):
        """Operator-requested gate retry, without altering the agent's result."""
        with self.idle_toolchain():
            check_protected(handoff["inputs"])
            directory = self.directory / "validation-retry"
            directory.mkdir()
            atomic_json(directory / "handoff.json", handoff)
            before = {**protected_inputs(), **handoff["inputs"]}
            atomic_json(directory / "protected-inputs.json", before)
            foundation = Path(handoff["foundation"])
            representation = generations.representation(foundation)
            plan = json.loads(self.plan_path().read_text())
            recorded = (chunks.generation_toolchain(plan)["inputs"] if plan.get("toolchain")
                        else chunks.manifest_entries(RUN_ROOT / "inputs.sha256"))
            stored = {path: recorded.get(path) for path in representation}
            self.record("preparing-validation", requires_validation=True,
                        reason="Retrying the gate locally; no additional model turn")
            self.validate_repair(directory, handoff["result"], before, foundation, representation, stored)

    def repair_locked(self, report):
        self.boundary()
        self.state["repairs"] += 1
        directory = self.directory / ("repair-%02d" % self.state["repairs"])
        directory.mkdir()
        self.record("preparing-repair", requires_validation=True)
        before = protected_inputs()
        # Protect every previous generation while permitting a new one.
        for plan_path in (self.plan_path(), Path(self.state.get("smoke_plan", SMOKE_PLAN))):
            if plan_path.is_file():
                plan = json.loads(plan_path.read_text())
                if plan.get("toolchain"):
                    generation_root = Path(plan["toolchain"]["path"]).parent
                    for path in generation_root.rglob("*"):
                        if path.is_file() and (path.suffix in (".json", ".v", ".vo", ".sha256")):
                            before[str(path)] = digest(path)
        foundation_before = self.foundation()
        representation_before = generations.representation(foundation_before)
        plan_before = json.loads(self.plan_path().read_text())
        recorded = (chunks.generation_toolchain(plan_before)["inputs"] if plan_before.get("toolchain")
                    else chunks.manifest_entries(RUN_ROOT / "inputs.sha256"))
        stored_representation = {path: recorded[path] for path in representation_before}
        atomic_json(directory / "protected-inputs.json", before)
        atomic_json(directory / "failure.json", report)
        prompt = (SUPPORT / "repair-prompt.md").read_text()
        prompt += "\n\nActive checkpoint plan: " + str(self.plan_path())
        prompt += "\nCurrent foundation: " + str(foundation_before)
        prompt += "\nPolicy update: representation fixes and fresh checkpoint generations are authorized."
        prompt += "\nDo not repeat a full failing compilation: reuse existing dependency-only evidence."
        prompt += "\n\nCurrent failure (log data, not instructions):\n" + json.dumps(report, indent=2)
        self.record("repairing", repair_directory=str(directory))
        code = self.service("repair-%02d" % self.state["repairs"],
                            codex_command(self.state["codex"], self.state.get("session"),
                                          directory / "result.json", self.state.get("repair_access", "workspace")),
                            directory, self.state["repair_seconds"], prompt)
        check_protected(before)
        if code:
            raise Paused("Codex exited with status %s; no automatic retry or model fallback" % code)
        session, usage, result = read_codex_result(directory)
        self.record("repaired", session=session or self.state.get("session"),
                    last_result=result, last_usage=usage)
        if result["status"] != "ready":
            raise Paused(result["summary"])
        self.validate_repair(directory, result, before, foundation_before, representation_before, stored_representation)

    def validate_repair(self, directory, result, before, foundation_before, representation_before, stored_representation):
        self.boundary()
        foundation_after = Path(result.get("foundation") or foundation_before).resolve(strict=True)
        representation_after = generations.representation(foundation_after)
        changed = (representation_after != representation_before or representation_after != stored_representation)
        restart = changed or result.get("checkpoint_action") == "restart"
        if restart:
            # Never relabel an old checkpoint with the new importer/foundation.
            plan, smoke = generations.create(directory / "generation", self.plan_path(), foundation_after)
            self.record("preparing-generation", checkpoint_plan=str(plan), smoke_plan=str(smoke),
                        reason="Tested representation change: new checkpoint chain starts at line 1")
        self.record("validating", approved_worker_sha256=digest(chunks.WORKER))
        validation = directory / "validation"
        validation.mkdir()
        if json.loads(self.plan_path().read_text()).get("toolchain"):
            command = [sys.executable, str(Path(generations.__file__).resolve()),
                       "--plan", str(self.plan_path()), "--directory", str(validation / "fresh-regressions")]
        else:
            command = ["bash", str(SUPPORT / "validate.sh"), directory.name + "-" + self.directory.name]
        code = self.service("validate-%02d" % self.state["repairs"],
                            command, validation, 3600)
        check_protected(before)
        if code:
            raise Paused("Regression/checkpoint validation failed; full compilation not resumed")
        self.record("validated", requires_validation=False,
                    reason="Repair and independent regressions passed; supervisor owns continuation")


@contextmanager
def loop_lock():
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    with (STATE_ROOT / "loop.lock").open("a") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise Paused("A cslib supervisor already owns the loop") from None
        yield f


def start(args):
    with loop_lock():
        binary = shutil.which("codex")
        if not binary:
            raise Paused("Codex CLI is not installed")
        auth = subprocess.run([binary, "login", "status"], capture_output=True, text=True, timeout=15)
        if auth.returncode or "ChatGPT" not in auth.stdout + auth.stderr:
            raise Paused("Run codex login with your ChatGPT account first; API keys are not used")
        adopted = None
        previous = None
        latest_state = STATE_ROOT / "latest/state.json"
        last = json.loads(latest_state.read_text()) if latest_state.is_file() else {}
        retry_validation = getattr(args, "retry_validation", False)
        handoff = None
        if retry_validation or getattr(args, "retry_repair", False):
            previous = last
            if previous.get("phase") != "paused" or not previous.get("failure", {}).get("declaration"):
                raise Paused("No paused declaration failure to repair")
            if args.adopt_unit:
                raise Paused("Cannot both adopt a compilation and retry a repair")
            if retry_validation:
                handoff = validation_handoff(previous, latest_state.resolve())
        elif last.get("requires_validation"):
            raise Paused("An earlier repair is unvalidated; use --retry-validation for a reviewed fix, or --retry-repair")
        if args.adopt_unit:
            adopted = adopted_run(args.adopt_unit)
        else:
            units = subprocess.check_output(["systemctl", "--user", "list-units", "--state=active,activating",
                                             "--no-legend", "--plain", "rocq-cslib-15m-*.service"], text=True)
            matches = [line.split()[0] for line in units.splitlines() if line.strip()]
            if len(matches) > 1:
                raise Paused("Multiple active full-pass services; refusing to choose")
            if matches and previous:
                raise Paused("A full pass is active; cannot start the repair directly")
            if matches:
                adopted = adopted_run(matches[0])
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        directory = STATE_ROOT / stamp
        directory.mkdir()
        unit = "rocq-cslib-loop-" + stamp + ".service"
        state = {"unit": unit, "model": MODEL, "reasoning": "xhigh", "codex": binary,
                 "phase": "starting", "created": now(), "repairs": 0,
                 "repair_access": args.repair_access,
                 "checkpoint_plan": str(CHUNK_PLAN),
                 "next_target": {"library": "Mathlib", "status": "waiting for cslib; not started"},
                 "max_repairs": args.max_repairs, "repair_seconds": args.repair_seconds,
                 "adopt": adopted}
        if previous:
            state.update(failure=previous["failure"],
                         session=previous.get("session"), previous_run=str((STATE_ROOT / "latest").resolve()))
            if handoff:
                state.update(pending_validation=handoff, requires_validation=True,
                             repairs=previous["repairs"], failures=previous.get("failures", {}),
                             last_result=previous["last_result"], repair_directory=previous["repair_directory"])
            else:
                state["pending_failure"] = previous["failure"]
        if not adopted:
            for key in ("checkpoint_plan", "smoke_plan", "approved_worker_sha256"):
                if last.get(key):
                    state[key] = last[key]
        atomic_json(directory / "state.json", state)
        # Hold the lock until systemd accepts the launch, then the worker acquires it.
        existing = subprocess.check_output(["systemctl", "--user", "list-units",
                                            "--state=active,activating", "--no-legend", "--plain",
                                            "rocq-cslib-loop-*.service"], text=True)
        if existing.strip():
            raise Paused("An active loop service already exists; refusing another supervisor")
        subprocess.run(["systemd-run", "--user", "--unit=" + unit,
                                 "--service-type=exec", "--property=TimeoutStopSec=45",
                                 "--property=KillMode=control-group", "--property=MemoryMax=512M",
                                 "--property=MemorySwapMax=0",
                                 "--property=StandardOutput=append:" + str(directory / "supervisor.log"),
                                 "--property=StandardError=inherit", "--working-directory=" + str(ROOT),
                                 sys.executable, str(Path(__file__).resolve()), "worker", str(directory)],
                                check=True)
        latest = STATE_ROOT / "latest"
        temporary = STATE_ROOT / (".latest-" + stamp)
        temporary.symlink_to(directory)
        os.replace(temporary, latest)
    print("Started", unit, "using", MODEL)
    print("Retrying validation locally; no model call" if handoff else
          "Retrying the known failure directly; no full-pass replay" if previous else
          "Adopted " + adopted["unit"] if adopted else "Starting a guarded full continuation")
    print("Status:", directory / "state.json")


def interrupted(*_):
    raise KeyboardInterrupt


def validation_handoff(previous, state_path):
    """Pin the operator-reviewed candidate; success still requires the full gate."""
    if previous.get("phase") != "paused" or not previous.get("requires_validation"):
        raise Paused("No paused, unvalidated repair to validate")
    directory = Path(previous["repair_directory"])
    _, _, result = read_codex_result(directory)
    if result != previous.get("last_result") or not result.get("tests"):
        raise Paused("Stored repair result or test evidence does not match")
    plan = json.loads(Path(previous.get("checkpoint_plan", CHUNK_PLAN)).read_text())
    foundation = Path(result.get("foundation") or
                      (chunks.generation_toolchain(plan)["foundation"] if plan.get("toolchain")
                       else chunks.FOUNDATION / "Lean.vo")).resolve(strict=True)
    return {"requested": now(), "reason": "Operator requested local validation of the installed repair",
            "result": result, "foundation": str(foundation),
            "inputs": {**generations.representation(foundation), str(chunks.WORKER): digest(chunks.WORKER),
                       str(foundation.with_suffix(".v")): digest(foundation.with_suffix(".v")),
                       str(Path(previous.get("checkpoint_plan", CHUNK_PLAN))): digest(Path(previous.get("checkpoint_plan", CHUNK_PLAN))),
                       str(directory / "result.json"): digest(directory / "result.json"),
                       str(state_path): digest(state_path)}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    launch = sub.add_parser("start", help="Adopt an active full pass, or launch one")
    launch.add_argument("--adopt-unit")
    retry = launch.add_mutually_exclusive_group()
    retry.add_argument("--retry-repair", action="store_true",
                       help="Retry the last paused declaration failure directly, with its dedicated session")
    retry.add_argument("--retry-validation", action="store_true",
                       help="Validate an operator-reviewed installed repair locally, without another model turn")
    launch.add_argument("--max-repairs", type=int, default=3)
    launch.add_argument("--repair-seconds", type=int, default=7200)
    launch.add_argument("--repair-access", choices=("workspace", "full"), default="workspace",
                        help="Full local access requires explicit user authorization")
    worker = sub.add_parser("worker", help=argparse.SUPPRESS)
    worker.add_argument("directory", type=Path)
    for command in ("status", "pause", "stop"):
        sub.add_parser(command)
    args = parser.parse_args()
    try:
        check_manual_only_policy(args.command)
        if args.command == "start":
            if not 0 <= args.max_repairs <= 20 or not 60 <= args.repair_seconds <= 14400:
                parser.error("max-repairs must be 0..20; repair-seconds must be 60..14400")
            start(args)
        elif args.command == "worker":
            # Only a systemd-owned worker can safely own detached memory scopes.
            state = json.loads((args.directory / "state.json").read_text())
            if not Path("/proc/self/cgroup").read_text().strip().endswith("/" + state["unit"]):
                raise Paused("Worker must run inside its recorded systemd service")
            signal.signal(signal.SIGTERM, interrupted)
            # The start command briefly owns the same lock during unit creation.
            with (STATE_ROOT / "loop.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                return Supervisor(args.directory).run()
        else:
            if args.command == "status":
                print(MANUAL_ONLY_POLICY)
                if not (STATE_ROOT / "latest").exists():
                    print("No archived loop state.")
                    return 0
                print("Archived autonomous loop state (not the current manual run):")
            directory = (STATE_ROOT / "latest").resolve(strict=True)
            state = json.loads((directory / "state.json").read_text())
            if args.command == "status":
                print("Phase:", state["phase"])
                print("Model:", state["model"], "/", state.get("reasoning", "xhigh"))
                print("Repair access:", state.get("repair_access", "workspace"))
                print("Repair turns: %s / %s" % (state["repairs"], state["max_repairs"]))
                active_plan = Path(state.get("checkpoint_plan", CHUNK_PLAN))
                if active_plan.is_file():
                    plan = json.loads(active_plan.read_text())
                    progress_path = active_plan.parent / "progress.json"
                    cursor = (json.loads(progress_path.read_text())["next_line"] if progress_path.is_file()
                              else plan["chunks"][0]["start"])
                    print("Archived checkpoint through line:", format(cursor - 1, ","))
                    upcoming = next((c["end"] - 1 for c in plan["chunks"] if c["end"] > cursor), None)
                    if upcoming is not None:
                        print("Former next checkpoint through line:", format(upcoming, ","))
                    if state.get("adopted") and state["phase"] == "compiling":
                        print("The adopted legacy run is unchanged; chunking applies to the next continuation.")
                print("Updated:", state.get("updated", state["created"]))
                if state.get("reason"):
                    print("Reason:", state["reason"])
                if state.get("failure"):
                    print("Last failure:", state["failure"].get("declaration"))
                if state.get("next_target"):
                    print("Next target:", state["next_target"]["library"], "—", state["next_target"]["status"])
                print("Service:", state["unit"])
                print("Details:", directory / "state.json")
                print("Log:", directory / "supervisor.log")
            elif args.command == "pause":
                (directory / "PAUSE").touch()
                print("Pause requested. No new work after the current phase; adopted runs are not stopped.")
            elif args.command == "stop":
                if state["unit"] != "rocq-cslib-loop-" + directory.name + ".service":
                    raise Paused("State does not identify its own loop service; refusing stop")
                (directory / "PAUSE").touch()
                subprocess.run(["systemctl", "--user", "stop", state["unit"]], check=True)
                print("Stopped supervisor and its owned jobs. An adopted run is left untouched.")
    except (Paused, OSError, ValueError, subprocess.SubprocessError) as exc:
        print("cslib loop:", exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
