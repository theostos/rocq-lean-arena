#!/usr/bin/env python3
"""Summarize observations, without claiming automatic root-cause analysis."""
from collections import Counter
import importlib.util
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / "mathlib-cache-measurement"
TARGET = "Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq"
spec = importlib.util.spec_from_file_location("cache_report", BASE / "report.py")
cache_report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache_report)


def extract(log):
    phases, entries, stacks, stack = [], [], [], None
    for line in log.splitlines():
        match = re.match(r"\[declare ([^]]+)\] " + re.escape(TARGET) + r" instance 0 cpu=([\d.]+)", line)
        if match:
            phases.append({"phase": match[1], "cpu": float(match[2])})
        match = re.match(r"\[conversion entry\] (\d+) cpu=([\d.]+) major=(\d+) (.+)", line)
        if match:
            entries.append({"call": int(match[1]), "cpu": float(match[2]),
                            "major_collections": int(match[3]), "comparison": match[4]})
        if line.startswith("[timeout stack]"):
            stack = {"header": line, "frames": []}
        elif stack is not None and line.startswith("#"):
            stack["frames"].append(line)
        elif stack is not None and line.startswith("[timeout stack end]"):
            stack["stopped_seconds"] = float(line.split("stopped_seconds=")[1])
            stacks.append(stack)
            stack = None
    return phases, entries, stacks


def kernel_events(events):
    stack, completed = [], []
    for event in events:
        if event.get("ph") == "B":
            stack.append(event)
        elif event.get("ph") == "E" and stack:
            begin = stack.pop()
            if begin["name"] != event["name"]:
                raise ValueError("Unbalanced kernel profile")
            if event["name"] == "Typeops.execute":
                completed.append({"wall_seconds": (float(event["ts"]) - float(begin["ts"])) / 1e6,
                                  "args": event.get("args", {})})
    return sorted(completed, key=lambda x: x["wall_seconds"], reverse=True)


def summarize(stage):
    cache_text = cache_report.summarize(stage)
    cut_path = stage / "diagnostic-cut.json"
    cut = json.loads(cut_path.read_text()) if cut_path.exists() else None
    phases, entries, stacks = extract((stage / "run.log").read_text(errors="replace"))
    last_path = stage / "last-conversion-entry.log"
    if last_path.exists():
        last_entries = extract(last_path.read_text())[1]
        if last_entries and (not entries or last_entries[-1]['call'] != entries[-1]['call']):
            entries += last_entries
    native = Counter(s["frames"][0] if s["frames"] else "No frames" for s in stacks)
    checks, profile_error = [], None
    try:
        profile = stage / "kernel-profile.json"
        if profile.stat().st_size > 64 * 1024**2:
            raise ValueError("Profile exceeds the 64 MiB analysis limit; retained for streaming analysis")
        checks = kernel_events(json.loads(profile.read_text())["traceEvents"])
    except (OSError, ValueError, KeyError) as error:
        profile_error = str(error)
    data = {"target": TARGET, "phases": phases, "conversion_entries": entries,
            "native_stacks": stacks, "longest_kernel_checks": checks[:10], "profile_error": profile_error,
            "diagnostic_cut": cut}
    (stage / "investigation.json").write_text(json.dumps(data, indent=2) + "\n")
    output = ["# Timeout investigation", "", f"Target: `{TARGET}`.", "",
              "This is an automatically generated evidence summary, not an automatic diagnosis.", "",
              "## Declaration phases", ""]
    if cut:
        output[4:4] = [f"Intentionally interrupted after {cut['target_cpu_seconds']:.3f} target CPU seconds to collect diagnostics; "
                       "this replay did not exhaust its configured 1800-second timeout. The separate full-duration baseline did.", ""]
    for before, after in zip(phases, phases[1:]):
        output.append(f"- {before['phase']} → {after['phase']}: {after['cpu'] - before['cpu']:.3f} CPU seconds.")
    output += ["", "## Conversion", "", f"Retained {len(entries)} top-level conversion entries during the target (thinned after 10,000; final entry retained)."]
    if entries:
        last = entries[-1]
        output += [f"Last recorded entry: call **{last['call']}**, CPU timestamp {last['cpu']:.3f}.",
                   "", f"`{last['comparison']}`", "",
                   "An entry names the top-level compared heads, not every recursive comparison. Without an exit marker, it alone does not prove which call owned the timeout."]
    output += ["", "## Kernel checking and allocation", "",
               "Longest `Typeops.execute` events across this replay (wall time, including debugger pauses):"]
    for check in checks[:3]:
        values = check["args"]
        output.append(f"- {check['wall_seconds']:.3f} s; conversion subtimes: {values.get('subtimes', {}).get('Conversion', 'not recorded')}; "
                      f"minor allocation: {values.get('minor_words', '?')}; major allocation: {values.get('major_words', '?')}; "
                      f"major/minor collections: {values.get('major_collect', '?')}/{values.get('minor_collect', '?')}.")
    if profile_error:
        output.append("Kernel profile incomplete/unavailable: " + profile_error)
    output += ["", "## Native stacks", "", f"Captured {len(stacks)} stacks; recorded stop overhead: "
               f"{sum(s['stopped_seconds'] for s in stacks):.3f} seconds (excludes signal-delivery/resume overhead).",
               "These are sparse wall-clock samples, not exact CPU percentages."]
    for frame, count in native.most_common(8):
        output.append(f"- {count} samples: `{frame}`")
    output += ["", cache_text.replace("# Dependency-cache measurement", "## Dependency-cache timings", 1),
               "", "## Interpretation still required", "",
               "Use the conversion call/head, full stacks, kernel subtimes, and cache timings together to locate the expensive comparison. "
               "Then test any proposed cause with a focused reproduction or a one-factor comparison. "
               "Logging/profiling overhead means this replay is not an uninstrumented speed benchmark. "
               "No proofs, conversion policy or checkpoints were changed."]
    text = "\n".join(output) + "\n"
    (stage / "REPORT.md").write_text(text)
    return text


if __name__ == "__main__":
    print(summarize(Path(sys.argv[1])))
