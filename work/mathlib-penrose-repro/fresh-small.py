#!/usr/bin/env python3
"""Use fresh expression IDs so the loaded prefix cannot reuse the old literal."""
from pathlib import Path
HERE = Path(__file__).resolve().parent
records = (HERE / 'Penrose.lean-export').read_text().splitlines()
literal = next(line.split()[2:] for line in records if line.startswith('7923 #ELS '))
assert records[-1] == '#HINT_OPAQUE 1726 7926 7927'
for size in (3000, 30000):
    export = HERE / f'FreshSmall{size}.lean-export'
    tail = ['7928 #ELS ' + ' '.join(literal[:size]), '7929 #EA 7922 7928',
            '7930 #EA 7849 7929', '7931 #EA 7930 7929', '7932 #EA 7850 7929',
            '#HINT_OPAQUE 1726 7931 7932']
    with export.open('x') as output:
        output.write('\n'.join(records[:-1] + tail) + '\n')
    original = (HERE / 'PenroseTargetLegacy.v').read_text()
    (HERE / f'FreshSmall{size}.v').write_text(original.replace(
        str(HERE / 'Penrose.lean-export'), str(export)).replace('9939 9940', '9939 9945'))
