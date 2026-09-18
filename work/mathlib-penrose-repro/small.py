#!/usr/bin/env python3
"""Diagnostic only: shorten the literal, preserving the reflexive proof shape."""
from pathlib import Path
HERE = Path(__file__).resolve().parent
for size in (3000, 30000):
    export = HERE / f'Small{size}.lean-export'
    with (HERE / 'Penrose.lean-export').open() as source, export.open('x') as dest:
        for line in source:
            if line.startswith('7923 #ELS '):
                line = ' '.join(line.split()[:size + 2]) + '\n'
            dest.write(line)
    original = (HERE / 'PenroseTargetLegacy.v').read_text()
    (HERE / f'Small{size}.v').write_text(original.replace(str(HERE / 'Penrose.lean-export'), str(export)))
