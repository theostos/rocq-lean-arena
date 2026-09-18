#!/usr/bin/env python3
"""Use the existing native fixture harness with a smaller, enforced 1 GiB cap."""
import importlib.util
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ALIGN = HERE.parent / 'kernel-alignment-pass'
spec = importlib.util.spec_from_file_location('small_native', ALIGN / 'run.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source, directory, *options = sys.argv[1:]
base_environment = module.replay.direct.environment
def environment(_):
    env = base_environment(1024)
    if 'ROCQ_MEMORY_OWNER_SERVICE' in os.environ:
        env['ROCQ_MEMORY_OWNER_SERVICE'] = os.environ['ROCQ_MEMORY_OWNER_SERVICE']
    return env
module.replay.direct.environment = environment
module.replay.direct.checking.IMPORTER = ALIGN / 'importer.1lqiqwaI'
sys.argv = [str(Path(__file__)), source, '--native', '--directory', directory, *options]
raise SystemExit(module.replay.main())
