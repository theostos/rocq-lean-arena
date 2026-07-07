#!/usr/bin/env python3
"""Print checker temporary directories recorded in arena result JSON files."""

from __future__ import annotations

import fnmatch
import json
import os
import re
from pathlib import Path


def main() -> int:
    checker = os.environ.get("CHECKER", "rocq-lean-import")
    test_pattern = os.environ.get("TEST", "*")
    results_dir = Path(os.environ.get("LKA_RESULTS_DIR", "_results"))
    marker = re.compile(r"Keeping temporary checker directory: (.+)")

    if not results_dir.is_dir():
        return 0

    tmpdirs: list[tuple[str, str]] = []
    for path in sorted(results_dir.glob(f"{checker}_*.json")):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue

        test_name = str(data.get("test", ""))
        if test_pattern and not fnmatch.fnmatch(test_name, test_pattern):
            continue

        text = f"{data.get('stderr', '')}\n{data.get('stdout', '')}"
        matches = marker.findall(text)
        if matches:
            tmpdirs.append((test_name, matches[-1]))

    if not tmpdirs:
        return 0

    print()
    print("Kept temporary checker directories:")
    for test_name, tmpdir in tmpdirs:
        print(f"  {test_name}: {tmpdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
