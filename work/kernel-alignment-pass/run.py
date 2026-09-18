#!/usr/bin/env python3
"""Guarded alignment regressions and the Scheme pullback replay from 21M."""
import importlib.util
import json
import os
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    'alignment_replay', HERE.parent / 'mathlib-basic-open-repro/run.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.TARGET = int(os.environ.get('ROCQ_ALIGNMENT_TARGET_LINE', '21660881'))
if not 21000001 <= replay.TARGET <= 22000000:
    raise ValueError('Expected a focus line in the 21M–22M segment')
replay.CHECKPOINT_END = 21000001

if __name__ == '__main__':
    # A diagnostic ABI rebuild is separate from the sealed producer toolchain.
    # Original checkpoint inputs are still verified by the unchanged harness;
    # pin the staged consumer plugin independently, before and after replay.
    importer = os.environ.get('ROCQ_ALIGNMENT_IMPORTER')
    inputs = {}
    extra_prefixes = []
    for value in filter(None, os.environ.get('ROCQ_ALIGNMENT_EXTRA_PREFIX', '').split(os.pathsep)):
        prefix = Path(value).resolve(strict=True)
        if prefix.parent != HERE:
            raise ValueError('Expected an alignment prefix directory')
        result_path, invocation_path = prefix / 'result.json', prefix / 'invocation.json'
        result = json.loads(result_path.read_text())
        invocation = json.loads(invocation_path.read_text())
        source = Path(invocation['command'][-1]).resolve(strict=True)
        artifact = source.with_suffix('.vo')
        if (source.parent != prefix or result['exit_code'] != 0 or
                replay.chunks.sha(artifact) != result['vo_sha256']):
            raise ValueError('Prefix is not a verified successful artifact')
        for path in (source, artifact, result_path, invocation_path):
            inputs[str(path)] = replay.chunks.sha(path)
        extra_prefixes.append(str(prefix))
    if extra_prefixes:
        base_environment = replay.direct.environment

        def environment(memory_mib):
            env = base_environment(memory_mib)
            env['ROCQPATH'] = os.pathsep.join(extra_prefixes)
            return env

        replay.direct.environment = environment
    if importer:
        importer = Path(importer).resolve(strict=True)
        if importer.parent != HERE or not importer.name.startswith('importer.'):
            raise RuntimeError('Expected an isolated alignment importer')
        inputs.update({str(p): replay.chunks.sha(p) for p in
                  (importer / 'src/lean_import.cmxs',
                   importer / 'src/META.coq-lean-import')})
        for pattern in ('*.ml', '*.mli', '*.mlg'):
            inputs.update({str(p): replay.chunks.sha(p)
                           for p in (importer / 'src').glob(pattern)})
        replay.direct.checking.IMPORTER = importer
        save_json = replay.chunks.save_json

        def record(path, data):
            if Path(path).name == 'invocation.json':
                data = dict(data, consumer_importer_inputs=inputs,
                            extra_prefixes=extra_prefixes, focus_line=replay.TARGET)
            return save_json(path, data)

        replay.chunks.save_json = record
        print('Consumer importer:', importer, inputs[str(importer / 'src/lean_import.cmxs')], flush=True)
    result = replay.main()
    replay.chunks.check_entries(inputs)
    raise SystemExit(result)
