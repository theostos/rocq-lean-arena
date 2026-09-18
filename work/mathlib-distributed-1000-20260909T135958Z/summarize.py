#!/usr/bin/env python3
"""Verify both completed experiments and write a compact comparison."""
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
results = []
for workers in (8, 1):
    receipt = json.loads((HERE / f'workers-{workers}/result.json').read_text())
    log = (HERE / f'workers-{workers}.log').read_text()
    finish = re.search(r'finished with status (-?\d+); cgroup peak=(\d+) KiB', log)
    if finish is None: raise RuntimeError(f'{workers}-worker guard did not finish')
    results.append({'workers':workers,'receipt':receipt,'exit_code':int(finish[1]),
                    'peak_cgroup_kib':int(finish[2])})
input_info = json.loads((HERE / 'input.json').read_text())
summaries = []
coverage = []
providers = []
for result in results:
    workers = result['workers']; directory = HERE / f'workers-{workers}'
    receipt = result['receipt']
    if result['exit_code'] != 0 or not receipt or not receipt.get('accepted'):
        raise RuntimeError(f'{workers} workers did not complete successfully')
    index_info = json.loads((directory / 'index/info.json').read_text())
    if index_info['certificate_sha256'] != input_info['prefix_sha256']:
        raise RuntimeError('benchmark inputs differ')
    with (directory / 'aggregate/All.vo').open('rb') as artifact:
        if hashlib.file_digest(artifact, 'sha256').hexdigest() != receipt['artifact_sha256']:
            raise RuntimeError('aggregate artifact changed')
    ids = []
    names = set()
    for path in (directory / 'artifacts').glob('*.json'):
        batch = json.loads(path.read_text()); ids.extend(batch['entries']); names.add(batch['batch'])
    if len(ids) != 1000 or len(set(ids)) != 1000 or receipt['entries'] != 1000:
        raise RuntimeError('original entry coverage differs')
    coverage.append(set(ids)); providers.append(names)
    summaries.append({'workers': workers, 'accepted_entries': len(ids),
                      'wall_seconds': receipt['total_seconds'],
                      'checking_wall_seconds': receipt['total_seconds'],
                      'peak_cgroup_gib': result['peak_cgroup_kib'] / 1048576,
                      'max_live_workers': receipt['max_live_workers'],
                      'committed_artifacts': receipt['batches'], 'attempts': receipt['attempts'],
                      'cpu_seconds': receipt['cpu_seconds']})
if coverage[0] != coverage[1]: raise RuntimeError('the runs checked different entries')
if providers[0] != providers[1]: raise RuntimeError('specialization providers differ')
ratio = summaries[1]['wall_seconds'] / summaries[0]['wall_seconds']
(HERE / 'comparison.json').write_text(json.dumps({'input': input_info, 'runs': summaries,
                                                 'one_over_eight_wall_ratio': ratio}, indent=2) + '\n')
rows = []
for run in summaries:
    seconds = round(run['wall_seconds']); minutes, seconds = divmod(seconds, 60)
    rows.append(f"| {run['workers']} | {minutes}m {seconds:02d}s | {run['peak_cgroup_gib']:.3f} GiB | "
                f"{run['max_live_workers']} | {run['accepted_entries']} | {run['attempts']} |")
text = f'''# Mathlib: 1,000 entries, eight workers followed by one

Both runs succeeded and saved `aggregate/All.vo`. Their exact original-entry
coverage and specialization-provider sets match; final artifact hashes were
verified. These are cold batch runs on the same certificate prefix, not a
comparison against the monolithic importer.

| Worker limit | End-to-end wall time | Peak cgroup memory | Maximum live workers | Entries | Attempts |
|---:|---:|---:|---:|---:|---:|
{chr(10).join(rows)}

One-worker wall time / eight-worker wall time: **{ratio:.3f}**. This is one
measurement per configuration. The eight-worker pool reached only two live
workers with the current batch plan; most execution was serial.

## Input and settings

The first 1,000 importer entries end at original Mathlib NDJSON line 66,309.
The prefix was copied verbatim, retaining complete declaration families.
SHA-256: `{input_info['prefix_sha256']}`.

Both runs used batch capacity 128, a shared 16 GiB memory budget, a 1.5 GiB
reservation per worker, a 1 GiB coordinator reservation, no workload swap,
a 600-second declaration timeout and a six-hour total deadline. The conversion
heuristic option was off in both. Foundation building, input indexing, checking,
discovery retries, artifact loading/saving and the final join are included.
The table uses the runner's measured wall times consistently for both runs;
outer guard startup/cleanup and shared input-prefix extraction are excluded.

The complete commands and toolchain fingerprints are in [commands.json](commands.json).
Raw results: [eight workers](workers-8/result.json), [one worker](workers-1/result.json).
Guard logs: [eight workers](workers-8.log), [one worker](workers-1.log).
Machine-readable comparison: [comparison.json](comparison.json).

## Fix and regression

Commit `98fcc0d` on `feature/distributed-import` restricts parent ownership to
actual inductive recursors. Ordinary definitions such as `Quot.rec` keep their
own source identity and specialization mask. Previously, `Quot.rec` was routed
to `Quot`, causing `Lean batch: missing instance owner entry` in the 500,000-line
experiment.

The new ordinary-definition regression failed with the old binary and passes
with the fix. All five real compiler integration cases and all 21 Python unit
tests pass. Evidence: [before log](regression-before/ordinary_rec_named_parallel.launcher.log)
and [after results](regression-after/integration-results.json).

The earlier 500,000-line eight-worker run failed after 533.53 seconds; its
one-worker comparison was cancelled when the user requested this smaller test.
Those incomplete runs are not used to calculate this comparison.
'''
(HERE / 'README.md').write_text(text)
print(json.dumps(summaries, indent=2))
print('One/eight wall ratio:', ratio)
