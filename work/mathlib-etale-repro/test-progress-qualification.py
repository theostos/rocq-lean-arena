#!/usr/bin/env python3
"""Check the continuation plan and run the full runner suite, including deadlines."""
import ast
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import run_chunked_import as chunks


def assigned(module, name):
    matches = [node.value for node in ast.walk(module) if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == name for target in node.targets)]
    assert len(matches) == 1, (name, len(matches))
    return matches[0]


validation = ast.parse((HERE / 'validate-v7-progress.py').read_text())
resume = ast.parse((HERE / 'resume-v7-progress.py').read_text())
commands = assigned(validation, 'commands')
labels = [ast.literal_eval(command.elts[0]) for command in commands.elts]
assert labels == ast.literal_eval(assigned(resume, 'expected')) and len(labels) == 19
assert 'commands[6:]' in (HERE / 'validate-v7-progress.py').read_text()
assert 'independent-progress.json' in (HERE / 'resume-v7-progress.py').read_text()
assert 'independent-progress.log' in (HERE / 'check-progress.py').read_text()
assert 'seconds = plan[\'line_timeout\']' in (HERE / 'check-progress.py').read_text()
assert 'checker_progress.py' in (HERE / 'check-progress.py').read_text()
old_inputs = json.loads((HERE / 'validation-etale-v7/inputs.json').read_text())
chunks.check_entries(old_inputs)

sources = list((ROOT / 'scripts/tests').glob('test_*.py')) + [
    ROOT / 'scripts/checker_progress.py', Path(__file__),
    *[HERE / name for name in ('check-progress.py', 'validate-v7-progress.py',
                              'resume-v7-progress.py', 'finish-v7-progress.py')]]
inputs = {str(path): chunks.sha(path) for path in sources}
command = [sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/tests']
log_path = HERE / 'deadline-tests.log'
with log_path.open('x') as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
report = log_path.read_text()
match = re.search(r'Ran (\d+) tests? in ', report)
skipped = re.search(r'^OK \(skipped=(\d+)\)', report, re.MULTILINE)
chunks.check_entries(inputs)
record = {'exit_code': result.returncode, 'tests': int(match[1]) if match else 0,
          'skipped': int(skipped[1]) if skipped else 0, 'command': command,
          'inputs': inputs, 'outputs': {str(log_path): chunks.sha(log_path)},
          'qualification_plan': 'All19stages retained; only6 verified successes reused; no kernel changes'}
chunks.save_json(HERE / 'deadline-tests.json', record)
print(json.dumps({k: record[k] for k in ('exit_code', 'tests', 'skipped')}), flush=True)
if result.returncode or record['tests'] < 215 or record['skipped'] > 2:
    raise SystemExit(result.returncode or 1)
