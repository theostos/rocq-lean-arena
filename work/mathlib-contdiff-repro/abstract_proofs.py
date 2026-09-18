#!/usr/bin/env python3
"""Diagnostic input only: replace dependency theorems by their assumptions."""
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
CONVERTER = ROOT / "_deps/lean-kernel-arena/checkers/rocq-lean-import/scripts/ndjson_to_lean_export.py"
spec = importlib.util.spec_from_file_location("converter", CONVERTER)
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class DiagnosticConverter(converter.StreamingConverter):
    def __init__(self, output, target):
        super().__init__(output)
        self.target = target
        self.full_names = {0: ""}
        self.abstracted = 0
        self.retained = 0

    def convert_name(self, obj):
        data = obj.get("str", obj.get("num"))
        prefix = self.full_names[data["pre"]]
        suffix = str(data.get("str", data.get("i")))
        self.full_names[obj["in"]] = prefix + ("." if prefix else "") + suffix
        super().convert_name(obj)

    def convert_theorem(self, decl):
        if self.full_names[decl["name"]] == self.target:
            self.retained += 1
            super().convert_theorem(decl)
        else:
            self.abstracted += 1
            self.convert_axiom(decl)


def main():
    source, destination = map(Path, sys.argv[1:3])
    target = sys.argv[3]
    with source.open() as stream, destination.open("x") as output:
        parser = DiagnosticConverter(output, target)
        for line in stream:
            parser.convert(json.loads(line))
        if parser.retained != 1:
            raise ValueError("Expected exactly one target theorem")
    print(f"Diagnostic only: {parser.abstracted} dependency proofs abstracted; target proof retained.")


if __name__ == "__main__":
    main()
