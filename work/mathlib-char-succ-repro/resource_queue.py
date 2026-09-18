"""Admission-only waiting; never retry a compiler that actually started."""
import json
from pathlib import Path
import re
import time
import uuid

RESERVE_MIB = 3072


def available_kib():
    for line in Path('/proc/meminfo').read_text().splitlines():
        if line.startswith('MemAvailable:'):
            return int(line.split()[1])
    raise RuntimeError('MemAvailable is unavailable')


def wait_for_memory(memory_mib, report):
    if not 1024 <= memory_mib <= 16384:
        raise ValueError('Validation budgets must stay between 1 and 16 GiB')
    required = (memory_mib + RESERVE_MIB) * 1024
    while (available := available_kib()) < required:
        report(required_kib=required, available_kib=available,
               memory_mib=memory_mib, reserve_mib=RESERVE_MIB)
        time.sleep(15)


def archive_unstarted(exit_code, log, record, *, fresh_directory=None):
    """Preserve a refused attempt, freeing only its designated output names.

    Callers supply fixed diagnostic paths, never production/checkpoint paths.
    The guard emits 'admitted' before starting the compiler. Require its exact
    pre-launch refusal and exit 75 in both records; OOMs/timeouts/proof failures
    and lock conflicts must not become automatic retries.
    """
    if exit_code != 75 or not log.is_file() or not record.is_file():
        return None
    if log.stat().st_size > 65536:
        return None
    text = log.read_text()
    refusal = (r'^memory guard: refusing launch: MemAvailable=\d+ KiB; '
               r'need at least reserve\(\d+\) \+ budget\(\d+\) = \d+ KiB$')
    if (not re.search(refusal, text, re.MULTILINE)
            or 'memory guard: admitted' in text
            or json.loads(record.read_text()).get('exit_code') != 75):
        return None
    suffix = '-admission-' + uuid.uuid4().hex
    if fresh_directory is not None:
        if (log.parent != fresh_directory or record.parent != fresh_directory
                or any(fresh_directory.rglob('*.vo'))
                or any(fresh_directory.rglob('*.vos'))):
            return None
        archived = fresh_directory.with_name(fresh_directory.name + suffix)
        fresh_directory.rename(archived)
        return [str(archived)]
    # An independent checker shares a directory with a successful compiler.
    # Archive only its two refused-check files; never move the compiled proof.
    archived = []
    for path in (log, record):
        target = path.with_name(path.name + suffix)
        path.rename(target)
        archived.append(str(target))
    return archived
