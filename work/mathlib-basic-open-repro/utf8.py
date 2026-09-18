"""Small, read-only-parent replay of the unchanged UTF-8 regression."""
import argparse
import fcntl
import json
from pathlib import Path
import shutil
import subprocess
import time
import run as harness

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('worker', type=Path)
p.add_argument('directory', type=Path)
p.add_argument('--source', type=Path, default=harness.HERE / 'Utf8Target.v')
p.add_argument('--prefix', type=Path)
p.add_argument('--trace-call', type=int)
a = p.parse_args()
worker = a.worker.resolve(strict=True)
stage = a.directory.resolve()
root, chunks = harness.ROOT, harness.chunks
original = a.source.resolve(strict=True)
parent = a.prefix.resolve(strict=True) if a.prefix else None
export = root / 'work/utf8-bitvec-two-repro/Utf8BitVec.lean-export'
foundation = root / 'work/cslib-from-start/20260908T183629430908Z/foundation'
with (chunks.OLD_RUN / 'launcher.lock').open('r') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    inputs = {str(path): chunks.sha(path) for path in
              (worker, foundation / 'Lean.vo', export, original,
               *([parent / 'Prefix.vo'] if parent else []))}
    stage.mkdir(exist_ok=False)
    source = stage / original.name
    shutil.copy2(original, source)
    env = harness.direct.environment(4096)
    env['LEAN_IMPORT_DECLARE_TRACE_LINE'] = '146567'
    env['ROCQ_DIAGNOSTIC_CONVERSION_ENTRIES'] = '1'
    if a.trace_call is not None:
        env['ROCQ_DIAGNOSTIC_CONVERSION_TRACE_CALL'] = str(a.trace_call)
    command = ['bash', str(harness.direct.checking.GUARD), 'timeout', '120s',
               str(worker), '--kind=compile', '-coqlib', env['COQLIB'],
               '-q', '-bytecode-compiler', 'no',
               '-R', str(harness.direct.checking.STDLIB), 'Stdlib',
               '-Q', str(foundation), 'LeanImport',
               '-I', str(root / '_worktrees/rocq-lean-import/compact-peano-importer-current/src'),
               *(['-Q', str(parent), ''] if parent else []),
               '-Q', str(stage), '', str(source)]
    chunks.save_json(stage / 'invocation.json', {'command': command, 'inputs': inputs})
    started = time.monotonic()
    with (stage / 'run.log').open('x') as log:
        result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
    chunks.check_entries(inputs)
    record = {'exit_code': result.returncode, 'wall_seconds': time.monotonic() - started,
              'worker_sha256': inputs[str(worker)]}
    if result.returncode == 0:
        record['vo_sha256'] = chunks.sha(source.with_suffix('.vo'))
    chunks.save_json(stage / 'result.json', record)
    print(json.dumps(record), flush=True)
    raise SystemExit(result.returncode)
