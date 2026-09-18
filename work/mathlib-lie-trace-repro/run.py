#!/usr/bin/env python3
"""Artifact-pinned, memory-guarded replay against the active foundation."""
import importlib.util
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('replay', HERE.parent / 'mathlib-with-terminal-repro/run.py')
replay = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replay)
replay.HERE = HERE
replay.GENERATION = HERE.parent / 'mathlib-alignment-5m-20260913-with-terminal'
replay.TARGET = 28200411
# Explicit, recorded one-factor experiments only. The production environment
# remains sanitized; never use these diagnostics for the resume approval.
environment = replay.direct.environment
def diagnostic_environment(memory):
    env = environment(memory)
    if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
        env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
    for key in ('ROCQ_DIAGNOSTIC_NO_DEPENDENCY_FIRST',
                'ROCQ_DIAGNOSTIC_PROCESS_STEP',
                'ROCQ_DIAGNOSTIC_NO_DIRECT_ARGUMENTS',
                'ROCQ_DIAGNOSTIC_CONGRUENCE_WORK',
                'ROCQ_DIAGNOSTIC_LEAN_DELTA',
                'ROCQ_DIAGNOSTIC_LATE_ETA',
                'ROCQ_DIAGNOSTIC_PROJECTION_FIRST',
                'ROCQ_DIAGNOSTIC_CONVERSION_CALL',
                'ROCQ_DIAGNOSTIC_CONGRUENCE_LIMIT',
                'ROCQ_DIAGNOSTIC_SIMULTANEOUS_DELTA',
                'ROCQ_DIAGNOSTIC_NO_UNIT_PROBES',
                'ROCQ_DIAGNOSTIC_ORACLE_FIRST',
                'ROCQ_DIAGNOSTIC_FAST_LIMIT',
                'ROCQ_EXPERIMENTAL_DEEP_FAST_TEST',
                'ROCQ_DIAGNOSTIC_DEPENDENCY_STATS'):
        if key in os.environ:
            env[key] = os.environ[key]
    return env
replay.direct.environment = diagnostic_environment
result = replay.main()
replay.chunks.save_json(Path(sys.argv[2]) / 'diagnostic-controls.json', {
    'wrapper_sha256': replay.chunks.sha(Path(__file__)),
    'environment': {key: value for key, value in diagnostic_environment(16384).items()
                    if key.startswith('ROCQ_DIAGNOSTIC_')},
})
raise SystemExit(result)
