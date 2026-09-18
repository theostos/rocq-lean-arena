#!/usr/bin/env python3
"""Summarize cumulative CPU counters, including a conservative boundary bound."""
import argparse
import json
from pathlib import Path
import re

TARGET = "Rep.barComplex.d_comp_diagonalSuccIsoFree_inv_eq"
QUANTUM = 1.0


def summarize(directory):
    records, start, end = [], None, None
    text = (directory / "run.log").read_text(errors="replace")
    for number, line in enumerate(text.splitlines(), 1):
        if line.startswith("[dependency profile]"):
            fields = dict(re.findall(r"(\w+)=(\S+)", line))
            fields = {k: v if k == "stage" else float(v) for k, v in fields.items()}
            fields["line"] = number
            records.append(fields)
        match = re.match(r"\[declare (start|done)\] " + re.escape(TARGET) + r" instance 0 cpu=([\d.]+)", line)
        if match:
            item = {"cpu": float(match[2]), "line": number}
            if match[1] == "start" and start is None:
                start = item
            elif match[1] == "done":
                end = item
    result = json.loads((directory / "result.json").read_text()) if (directory / "result.json").exists() else {}
    data = {"target": TARGET, "result": result, "start": start, "end": end,
            "sample_quantum_cpu_seconds": QUANTUM, "profile_samples": len(records)}
    output = ["# Dependency-cache measurement", "", f"Target: `{TARGET}`.", ""]
    final = next((r for r in reversed(records) if r["stage"] == "exit"), None)
    if start is None or final is None:
        output += ["Measurement incomplete: target-start or clean-exit counters are missing.",
                   "Inspect `run.log` and `result.json`; do not infer a cache percentage."]
        data["complete"] = False
    else:
        if end is None:
            end = {"cpu": final["cpu"], "line": final["line"]}
            data["end"] = end
            data["includes_error_cleanup"] = True
        before = max((r for r in records if r["line"] < start["line"]), key=lambda r: r["line"])
        after = max((r for r in records if r["line"] <= end["line"]), key=lambda r: r["line"])
        elapsed = end["cpu"] - start["cpu"]
        bounds = {}
        for key in ("query_cpu", "build_cpu"):
            start_slack = min(QUANTUM, max(0., start["cpu"] - before["cpu"]))
            end_slack = 0. if after["stage"] == "exit" else min(QUANTUM, max(0., end["cpu"] - after["cpu"]))
            lower = max(0., after[key] - before[key] - start_slack - 0.002)
            upper = max(lower, after[key] - before[key] + end_slack + 0.002)
            bounds[key] = {"lower_seconds": lower, "upper_seconds": upper,
                           "upper_percent": 100 * upper / elapsed if elapsed > 0 else None}
        data.update(complete=True, target_cpu_seconds=elapsed, bounds=bounds, final=final,
                    before_start=before, before_end=after)
        output += [f"- Exit status: **{result.get('exit_code', 'unknown')}**.",
                   f"- Target interval: **{elapsed:.2f} CPU seconds**."]
        for key, label in (("query_cpu", "All dependency queries"), ("build_cpu", "Cache construction (included above)")):
            b = bounds[key]
            output.append(f"- {label}: **{b['lower_seconds']:.3f}–{b['upper_seconds']:.3f} CPU seconds**, at most **{b['upper_percent']:.3f}%** of the target interval.")
        output += ["", "`build_cpu` includes nested misses only once; it is a subset of `query_cpu`.",
                   "Construction includes both newly demanded entries and entries rebuilt after reload; it bounds the latter's cost.",
                   "Interrupted queries/builds are counted before the exception propagates.",
                   "Bounds account for the one-CPU-second snapshot interval and rounded declaration timestamps.",
                   "For a timeout, the interval ends at process exit and includes error-reporting cleanup.",
                   "", "These are instrumented CPU measurements, not wall time or a cache-memory measurement.",
                   "Timing/counter overhead can slow this replay; no full cache-on/cache-off speedup is inferred.",
                   "The replay preserves the 9M checkpoint, intervening input, module name and proof bodies."]
    (directory / "measurement.json").write_text(json.dumps(data, indent=2) + "\n")
    (directory / "REPORT.md").write_text("\n".join(output) + "\n")
    return "\n".join(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    print(summarize(parser.parse_args().directory))
