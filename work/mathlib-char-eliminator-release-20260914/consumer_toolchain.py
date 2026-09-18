#!/usr/bin/env python3
"""Explicit ABI-only importer migration, without changing producer manifests.

The approved certificate is itself hash-pinned by the launcher. Old checkpoint
inputs remain mandatory. New checkpoints additionally bind this adapter, the
certificate, the rebuilt consumer and the validation evidence. No digest check
is disabled and no existing artifact/profile/seal is rewritten.
"""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks

FORMAT = 'rocq-abi-consumer-v1'
SOURCE_SUFFIXES = {'.ml', '.mli', '.mlg', '.v', '.mlpack', '.mllib'}


def require(condition, message):
    if not condition:
        raise chunks.Refused(message)


def sources(importer):
    result = {}
    for path in (importer / 'src').iterdir():
        if path.suffix in SOURCE_SUFFIXES or path.name == 'dune':
            require(path.is_file() and not path.is_symlink(), 'Unexpected source: ' + str(path))
            result[str(path.relative_to(importer))] = chunks.sha(path)
    require('src/lean.ml' in result and 'src/Lean.v' in result,
            'Incomplete importer source inventory')
    return result


def consumer_inputs(producer, consumer):
    original = Path(producer['importer'])
    require(consumer != original, 'Expected a separately built consumer')
    inventory = sources(original)
    require(sources(consumer) == inventory, 'Consumer is not an ABI-only source rebuild')
    inputs = {}
    for relative, digest in inventory.items():
        inputs[str(original / relative)] = digest
        inputs[str(consumer / relative)] = digest
    # Include every runtime importer input that the producer manifest binds,
    # e.g. the plugin, findlib metadata and Yojson runtime.
    for name in producer['inputs']:
        path = Path(name)
        if path.is_relative_to(original):
            replacement = consumer / path.relative_to(original)
            inputs[str(replacement)] = chunks.sha(replacement)
    plugin = consumer / 'src/lean_import.cmxs'
    require(str(plugin) in inputs, 'Producer did not bind the importer plugin')
    inputs[str(Path(__file__))] = chunks.sha(Path(__file__))
    inputs[str(chunks.WORKER)] = chunks.sha(chunks.WORKER)
    return inputs


def make_certificate(plan_path, consumer, validation_inputs):
    """Build a manifest; the caller must first approve the named validation."""
    plan_path = plan_path.resolve(strict=True)
    consumer = consumer.resolve(strict=True)
    require(bool(validation_inputs), 'Missing validation evidence')
    plan = chunks.load_plan(plan_path)
    producer = chunks.generation_toolchain(plan)
    chunks.check_entries(producer['inputs'])
    inputs = dict(validation_inputs)
    chunks.check_entries(inputs)
    additions = consumer_inputs(producer, consumer)
    require(all(path not in inputs or inputs[path] == digest
                for path, digest in additions.items()), 'Conflicting validation inputs')
    inputs.update(additions)
    return {'format': FORMAT, 'plan': str(plan_path), 'plan_sha256': chunks.sha(plan_path),
            'producer_toolchain': plan['toolchain'], 'producer_importer': producer['importer'],
            'consumer_importer': str(consumer), 'worker_sha256': chunks.sha(chunks.WORKER),
            'validation_inputs': dict(validation_inputs), 'inputs': inputs}


@contextmanager
def installed_consumer(certificate_path, expected_sha256):
    certificate_path = certificate_path.resolve(strict=True)
    require(chunks.sha(certificate_path) == expected_sha256, 'Consumer certificate changed')
    certificate = json.loads(certificate_path.read_text())
    require(certificate['format'] == FORMAT, 'Unsupported consumer certificate')
    plan_path = Path(certificate['plan'])
    require(plan_path.is_absolute() and chunks.sha(plan_path) == certificate['plan_sha256'],
            'Consumer certificate belongs to another plan')
    plan = chunks.load_plan(plan_path)
    original_loader = chunks.generation_toolchain

    def loader(requested):
        require(requested == plan, 'Consumer profile requested for another plan')
        require(chunks.sha(plan_path) == certificate['plan_sha256'], 'Plan changed')
        require(chunks.sha(certificate_path) == expected_sha256, 'Consumer certificate changed')
        require(plan['toolchain'] == certificate['producer_toolchain'], 'Producer profile changed')
        producer = original_loader(plan)
        require(producer['importer'] == certificate['producer_importer'], 'Producer importer changed')
        consumer = Path(certificate['consumer_importer'])
        require(consumer.is_absolute(), 'Consumer path must be absolute')
        required = consumer_inputs(producer, consumer)
        require(all(certificate['inputs'].get(p) == h for p, h in required.items()),
                'Unpinned or changed consumer input')
        require(certificate['worker_sha256'] == chunks.sha(chunks.WORKER),
                'Consumer worker is not the approved worker')
        require(bool(certificate['validation_inputs']) and all(
            certificate['inputs'].get(p) == h
            for p, h in certificate['validation_inputs'].items()), 'Unbound validation evidence')
        chunks.check_entries(producer['inputs'])
        chunks.check_entries(certificate['inputs'])
        inputs = dict(producer['inputs'])
        for path, digest in certificate['inputs'].items():
            require(path not in inputs or inputs[path] == digest, 'Conflicting producer input')
            inputs[path] = digest
        inputs[str(certificate_path)] = expected_sha256
        return dict(producer, importer=str(consumer), findlib_path=str(consumer / '_build/findlib'),
                    worker_sha256=certificate['worker_sha256'], inputs=inputs,
                    abi_consumer_certificate=str(certificate_path))

    loader(plan)  # Fail closed before installing any process-local override.
    chunks.generation_toolchain = loader
    try:
        yield plan_path, plan
    finally:
        chunks.generation_toolchain = original_loader


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--certificate', required=True, type=Path)
    parser.add_argument('--sha256', required=True)
    args = parser.parse_args()
    require(not any(k.startswith(('ROCQ_DIAGNOSTIC_', 'ROCQ_EXPERIMENTAL_',
                                 'LEAN_IMPORT_')) for k in os.environ),
            'Diagnostic/import overrides are not permitted for a production resume')
    import mathlib_ndjson_loop as loop
    with installed_consumer(args.certificate, args.sha256) as (plan_path, plan):
        # Runtime configuration and progress discovery must name the same
        # consumer as the chunk compiler. Restore process globals on failure.
        original_importer = loop.direct.checking.IMPORTER
        loop.direct.checking.IMPORTER = Path(chunks.generation_toolchain(plan)['importer'])
        try:
            return loop.run(plan_path.parent.parent, False, plan['memory_mib'],
                            plan['interval'], plan['line_timeout'])
        finally:
            loop.direct.checking.IMPORTER = original_importer


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (chunks.Refused, OSError, KeyError, ValueError) as exc:
        print('consumer migration:', exc, file=sys.stderr)
        raise SystemExit(65)
