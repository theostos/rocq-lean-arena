#!/usr/bin/env python3
"""Snapshot and summarize existing logs; never invoke or signal a checker."""
from collections import Counter, defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LINE = re.compile(r"^line (\d+): (.+)$")
TRACE = re.compile(r"^\[declare ([^]]+)\] (.+) instance (\d+) cpu=([\d.]+) heap_words=(\d+) major=(\d+)$")
SAMPLE = re.compile(r"^\[diagnostic stack\] (\S+) time=([\d.]+)")
GUARD = re.compile(r"memory guard: status (\S+):.*scope RSS=(\d+) KiB;.*MemAvailable=(\d+) KiB")


def snapshot(path):
    target = HERE / "snapshots" / path.relative_to(ROOT)
    if not target.exists():
        size = path.stat().st_size
        with path.open("rb") as stream:
            content = stream.read(size)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    content = target.read_bytes()
    return content.decode(errors="replace"), {
        "path": str(path.relative_to(ROOT)), "snapshot": str(target.relative_to(ROOT)),
        "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest(),
    }


def family(frames):
    text = "\n".join(frames)
    if any(word in text for word in ("__pack_lean_state_", "__write_graph_", "__make_index_")):
        return "checkpoint_packing"
    if re.search(r"camlEnviron__(?:search|direct_constant_dependencies|constant_depends_on)_", text):
        return "dependency_reachability"
    if "camlConversion__" in text:
        return "conversion"
    if "camlAcyclicGraph__" in text or "camlUGraph__" in text:
        return "universes"
    if any(word in text for word in ("camlMemory__intern", "caml_input_value", "caml_intern", "camlMarshal")):
        return "serialization"
    return "other"


def parse(path, text):
    samples, trace, starts, pairs, errors = [], [], {}, [], []
    input_names = {}
    name, export_line, after_done, current = None, None, False, None
    guard = []
    for number, raw in enumerate(text.splitlines(), 1):
        match = LINE.match(raw)
        if match:
            export_line, name = int(match[1]), match[2]
            input_names.setdefault(export_line, {"name": name, "log_line": number})
            after_done = False
        if raw == "Done!":
            after_done = True
        match = SAMPLE.match(raw)
        if match:
            current = {"signal": match[1], "epoch": float(match[2]), "log_line": number,
                       "export_line": export_line, "last_printed": name,
                       "after_import_done": after_done, "frames": [],
                       "traced_context": trace[-1] if trace and trace[-1]["export_line"] == export_line else None}
            samples.append(current)
        elif current is not None and raw.startswith("#") and re.match(r"^#\d+\s", raw):
            current["frames"].append(raw)
        match = TRACE.match(raw)
        if match:
            stage, declaration, instance, cpu, heap, major = match.groups()
            item = {"stage": stage, "name": declaration, "instance": int(instance),
                    "cpu": float(cpu), "heap_words": int(heap), "major": int(major), "log_line": number,
                    "export_line": export_line}
            trace.append(item)
            if stage.startswith("before "):
                starts[(declaration, instance, stage[7:])] = item
            elif stage.startswith("after "):
                previous = starts.pop((declaration, instance, stage[6:]), None)
                if previous:
                    pairs.append({"name": declaration, "instance": int(instance), "phase": stage[6:],
                                  "cpu_seconds": round(item["cpu"] - previous["cpu"], 3),
                                  "start_log_line": previous["log_line"], "end_log_line": number})
        if "Error at line " in raw or "Lean import line timed out" in raw or "Insufficient disk" in raw:
            errors.append({"log_line": number, "text": raw})
        match = GUARD.search(raw)
        if match:
            guard.append({"epoch": datetime.fromisoformat(match[1]).timestamp(),
                          "rss_kib": int(match[2]), "available_kib": int(match[3])})
    for sample in samples:
        sample["family"] = family(sample["frames"])
    groups = defaultdict(list)
    for sample in samples:
        groups[(sample["export_line"], sample["last_printed"], sample["after_import_done"])].append(sample)
    stalls = [{"export_line": key[0], "last_printed": key[1], "after_import_done": key[2],
               "samples": len(items), "sample_span_seconds": round(items[-1]["epoch"]-items[0]["epoch"], 3),
               "families": dict(Counter(s["family"] for s in items)),
               "sample_log_lines": [s["log_line"] for s in items]} for key, items in groups.items()]
    totals = defaultdict(float)
    for pair in pairs:
        totals[pair["phase"]] += pair["cpu_seconds"]
    return {"path": str(path.relative_to(ROOT)), "samples": samples, "stalls": stalls,
            "input_names": input_names,
            "trace_events": trace, "trace_pairs": pairs, "phase_totals_cpu": dict(totals),
            "errors": errors, "guard": guard,
            "done_markers": text.splitlines().count("Done!"),
            "last_printed": name, "last_export_line": export_line}


def main():
    paths = set()
    existing = HERE / "manifest.json"
    if existing.exists():
        paths.update(ROOT / item["path"] for item in json.loads(existing.read_text())
                     if item["path"].endswith(".log"))
    else:
        for directory in (ROOT / "work/mathlib-ndjson/attempts", ROOT / "work/mathlib-from-start",
                          ROOT / "work/mathlib-contdiff-repro"):
            paths.update(path for path in directory.rglob("*.log") if "latest" not in path.parts)
    records, manifest = [], []
    for path in sorted(paths):
        text, identity = snapshot(path)
        manifest.append(identity)
        records.append(parse(path, text))
    for name in ("progress.json", "toolchain.json", "source.json", "timeout-override.json"):
        _, identity = snapshot(ROOT / "work/mathlib-ndjson" / name)
        manifest.append(identity)
    stamp = HERE / "captured-at.txt"
    if not stamp.exists():
        stamp.write_text(datetime.now(timezone.utc).isoformat() + "\n")
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (HERE / "analysis.json").write_text(json.dumps(records, indent=2) + "\n")
    rows = ["log\tinput_line\tinput_name\tsamples\tobserved_span_seconds\tfamilies\tfirst_sample_log_line"]
    for record in records:
        if "/mathlib-ndjson/" not in record["path"]:
            continue
        inputs = defaultdict(list)
        for sample in record["samples"]:
            if not sample["after_import_done"]:
                inputs[sample["export_line"]].append(sample)
        for number, samples in inputs.items():
            rows.append("\t".join(map(str, (record["path"], number,
                record["input_names"][number]["name"], len(samples),
                round(samples[-1]["epoch"] - samples[0]["epoch"], 3),
                dict(Counter(s["family"] for s in samples)), samples[0]["log_line"]))))
    (HERE / "slow-inputs.tsv").write_text("\n".join(rows) + "\n")
    rows = ["log\tobserved_worker_seconds\tpeak_sampled_rss_gib\tminimum_available_gib"]
    for record in records:
        guard = record["guard"]
        if "/mathlib-ndjson/" in record["path"] and guard:
            rows.append("\t".join(map(str, (record["path"],
                round(guard[-1]["epoch"] - guard[0]["epoch"], 3),
                round(max(g["rss_kib"] for g in guard) / 1024**2, 3),
                round(min(g["available_kib"] for g in guard) / 1024**2, 3)))))
    (HERE / "worker-times.tsv").write_text("\n".join(rows) + "\n")
    for record in records:
        if "/mathlib-ndjson/" not in record["path"] or not (record["samples"] or record["errors"]):
            continue
        print(record["path"])
        for stall in record["stalls"]:
            print(" ", json.dumps(stall))
        if record["trace_events"]:
            trace = record["trace_events"]
            print("  trace CPU span:", round(trace[-1]["cpu"]-trace[0]["cpu"],3),
                  "starts:", sum(e["stage"] == "start" for e in trace),
                  "phase totals (nested translation phases overlap):", record["phase_totals_cpu"])
        for error in record["errors"]:
            print(" ", error)
    print("Captured", len(manifest), "files; analysis:", HERE / "analysis.json")


if __name__ == "__main__":
    main()
