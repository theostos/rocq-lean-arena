#!/usr/bin/env python3
"""Pinned, guarded replay of one existing small importer regression."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks
import run_cslib_ndjson as direct


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('group')
    parser.add_argument('test')
    parser.add_argument('directory')
    parser.add_argument('--prefix', type=Path)
    parser.add_argument('--trace-call', type=int)
    parser.add_argument('--entries', action='store_true')
    args = parser.parse_args()
    original = (ROOT / 'work' / args.group / (args.test + '.v')).resolve(strict=True)
    if original.parent.parent != ROOT / 'work':
        raise ValueError('Expected an existing work fixture')
    stage = HERE / args.directory
    if stage.parent != HERE or stage.exists():
        raise ValueError('Expected a new alignment directory')
    importer = Path(os.environ['ROCQ_ALIGNMENT_IMPORTER']).resolve(strict=True)
    if importer.parent != HERE or not importer.name.startswith('importer.'):
        raise ValueError('Expected isolated consumer')
    foundation = HERE / 'final-gates-12/fresh-smoke/foundation/Lean.vo'
    inputs = {str(p): chunks.sha(p) for p in
              [original, foundation, chunks.WORKER, importer / 'src/lean_import.cmxs']}
    extra = []
    if args.prefix:
        prefix = args.prefix.resolve(strict=True)
        record_path = prefix / 'result.json'
        record = json.loads(record_path.read_text())
        artifact = prefix / (record['module'] + '.vo')
        if prefix.parent != HERE or record['exit_code'] or chunks.sha(artifact) != record['vo_sha256']:
            raise ValueError('Expected verified diagnostic prefix')
        inputs[str(record_path)] = chunks.sha(record_path)
        inputs[str(artifact)] = chunks.sha(artifact)
        extra = ['-Q', str(prefix), '']
    chunks.check_disk(HERE)
    stage.mkdir()
    source = stage / original.name
    shutil.copy2(original, source)
    for export in original.parent.glob('*.lean-export'):
        inputs[str(export)] = chunks.sha(export)
        (stage / export.name).symlink_to(export)
    env = direct.environment(4096)
    env['OCAMLPATH'] = str(chunks.KERNEL / '_build/install/default/lib') + ':' + str(importer / '_build/findlib')
    if args.trace_call is not None:
        env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(args.trace_call)
    if args.entries:
        env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
    command = ['bash', str(direct.checking.GUARD), 'timeout', '600s',
               str(chunks.WORKER), '--kind=compile', '-coqlib', env['COQLIB'],
               '-q', '-bytecode-compiler', 'no', '-R', str(direct.checking.STDLIB), 'Stdlib',
               '-I', str(importer / 'src'), '-Q', str(foundation.parent), 'LeanImport',
               *extra, '-Q', str(stage), '', str(source)]
    chunks.save_json(stage / 'invocation.json', {'command': command, 'inputs': inputs})
    started = time.monotonic()
    with (stage / 'run.log').open('x') as log:
        result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
    chunks.check_entries(inputs)
    record = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
              'module': source.stem, 'worker_sha256': inputs[str(chunks.WORKER)]}
    if not result.returncode:
        record['vo_sha256'] = chunks.sha(source.with_suffix('.vo'))
    chunks.save_json(stage / 'result.json', record)
    print(record, flush=True)
    return result.returncode


if __name__ == '__main__':
    raise SystemExit(main())
