#!/usr/bin/env python3
"""One-factor controls on the same isolated, guarded replay harness."""
import argparse
import sys
from run import harness

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('--strategy', choices=['default', 'no-direct-arguments',
                                          'projection-first'], default='default')
parser.add_argument('--memo-limit', type=int)
parser.add_argument('--dependency-stats', action='store_true')
parser.add_argument('--path', action='store_true')
parser.add_argument('--no-constructor-preference', action='store_true')
parser.add_argument('--no-projected-wrapper', action='store_true')
options, remaining = parser.parse_known_args()
if options.memo_limit is not None and not 1 <= options.memo_limit <= 1048576:
    parser.error('--memo-limit must be between 1 and 1048576')

controls = {}
if options.no_projected_wrapper:
    controls['ROCQ_DIAGNOSTIC_NO_PROJECTED_WRAPPER'] = '1'
if options.no_constructor_preference:
    controls['ROCQ_DIAGNOSTIC_NO_CONSTRUCTOR_PREFERENCE'] = '1'
if options.path:
    controls['ROCQ_DIAGNOSTIC_CONVERSION_PATH'] = '1'
if options.strategy != 'default':
    controls['ROCQ_DIAGNOSTIC_' + options.strategy.upper().replace('-', '_')] = '1'
if options.memo_limit is not None:
    controls['ROCQ_DIAGNOSTIC_CONVERSION_MEMO_LIMIT'] = str(options.memo_limit)
if options.dependency_stats:
    controls['ROCQ_DIAGNOSTIC_DEPENDENCY_STATS'] = '1'

base_environment = harness.direct.environment
def environment(memory_mib):
    env = base_environment(memory_mib)
    env.update(controls)
    return env
harness.direct.environment = environment

base_save_json = harness.chunks.save_json
def save_json(path, data):
    if path.name == 'invocation.json':
        data = {**data, 'diagnostic_controls': controls}
    return base_save_json(path, data)
harness.chunks.save_json = save_json

sys.argv = [sys.argv[0], *remaining]
raise SystemExit(harness.main())
