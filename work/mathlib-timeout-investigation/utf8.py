"""Recheck the unchanged UTF-8 dependency fixture with a selected kernel."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts'))
import run_cslib_from_start as runtime
import run_chunked_import as chunks

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--worker', type=Path, default=chunks.WORKER)
parser.add_argument('--fixture', type=Path, default=ROOT / 'work/utf8-bitvec-two-repro')
args = parser.parse_args()
original = args.fixture.resolve()
stage = Path(tempfile.mkdtemp(prefix=original.name + '-', dir=HERE))
shutil.copy2(original / 'Fresh.v', stage / 'Fresh.v')
exports = list(original.glob('*.lean-export'))
for export in exports:
    (stage / export.name).symlink_to(export)
env = runtime.environment(4096)
env['ROCQ_STACK_KIB'] = '8192'
command = ['bash', str(runtime.GUARD), 'timeout', '600s', str(args.worker.resolve()),
           '--kind=compile', '-coqlib', env['COQLIB'], '-q', '-bytecode-compiler', 'no',
           '-R', str(runtime.STDLIB), 'Stdlib', '-I', str(runtime.IMPORTER / 'src'),
           '-Q', str(ROOT / 'work/cslib-from-start/20260908T183629430908Z/foundation'), 'LeanImport',
           '-Q', str(stage), '', str(stage / 'Fresh.v')]
inputs = [args.worker, original / 'Fresh.v', *exports,
          runtime.IMPORTER / 'src/lean_import.cmxs',
          ROOT / 'work/cslib-from-start/20260908T183629430908Z/foundation/Lean.vo']
(stage / 'invocation.json').write_text(json.dumps({'command': command,
    'inputs': {str(p): chunks.sha(p) for p in inputs}}, indent=2) + '\n')
print(stage, flush=True)
with (stage / 'run.log').open('x') as log:
    result = subprocess.run(command, cwd=stage, env=env, stdout=log, stderr=subprocess.STDOUT)
(stage / 'result.json').write_text(json.dumps({'exit_code': result.returncode}) + '\n')
raise SystemExit(result.returncode)
