#!/usr/bin/env python3
"""Short, command-timed frontend diagnostic; not validation evidence."""
import json
from pathlib import Path
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct
directory = ROOT / 'work/kernel-alignment-pass/char-eliminator-native'
record = json.loads((directory / 'invocation.json').read_text())
command = record['command']
command = [arg.replace('2400s', '30s') for arg in command]
command.insert(-1, '-time')
with (directory / 'frontend-time.log').open('x') as output:
    result = subprocess.run(command, env=direct.environment(4096), stdout=output, stderr=subprocess.STDOUT)
print(result.returncode)
