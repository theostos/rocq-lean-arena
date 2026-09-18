#!/usr/bin/env python3
"""Bound rocqchk by declaration progress, not by the size of the whole library.

Run INSIDE the existing memory guard. Only rocqchk's constant-start messages
for the requested module reset the deadline; guard chatter and diagnostics do
not. All proofs are still checked in one ordinary rocqchk invocation. A start
message is progress, never evidence that that declaration passed. Only exit 0
is success. Startup, unreported work, and finalization are bounded as well.
"""
import argparse
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time


class Progress:
    def __init__(self, module, seconds, now):
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', module):
            raise ValueError('Expected a simple module name')
        if not math.isfinite(seconds) or seconds <= 0:
            raise ValueError('Deadline must be positive and finite')
        self.module, self.seconds = module, seconds
        self.started = self.changed = now
        self.current = None
        self.count = 0
        self.pending = b''
        self.dropping = False
        self.longest_seconds = 0.0
        self.longest_declaration = None
        self.prefix = ('  checking cst:' + module + '.').encode()

    def expired(self, now):
        return now - self.changed >= self.seconds

    def feed(self, chunk, now):
        # Never retain an arbitrarily large diagnostic line. Ignore it until
        # its newline instead of interpreting a suffix as a progress marker.
        for part in chunk.splitlines(keepends=True):
            complete = part.endswith(b'\n')
            if not self.dropping:
                if len(self.pending) + len(part) > 65536:
                    self.pending, self.dropping = b'', True
                else:
                    self.pending += part
            if complete:
                if not self.dropping:
                    line = self.pending.rstrip(b'\r\n')
                    if line.startswith(self.prefix):
                        name = line[len(b'  checking cst:'):].decode('utf-8', 'replace')
                        if name != self.current:
                            duration = now - self.changed
                            if self.current is not None and duration > self.longest_seconds:
                                self.longest_seconds = duration
                                self.longest_declaration = self.current
                            self.current, self.changed = name, now
                            self.count += 1
                self.pending, self.dropping = b'', False

    def record(self, now, phase='running', **extra):
        return {'phase': phase, 'module': self.module,
                'declaration_timeout_seconds': self.seconds,
                'elapsed_seconds': now - self.started,
                'seconds_without_new_declaration': now - self.changed,
                'last_declaration': self.current, 'declarations_started': self.count,
                'longest_completed_interval_seconds': self.longest_seconds,
                'longest_completed_interval_declaration': self.longest_declaration,
                **extra}


def save(path, record):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(record, indent=2) + '\n')
    temporary.replace(path)


def stop_owned(process, grace=5):
    # This Popen was launched with start_new_session=True. The memory guard
    # independently accounts for and cleans every descendant in its cgroup.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def run(command, module, seconds, progress_path, output, *, grace=5):
    progress = Progress(module, seconds, time.monotonic())
    if progress_path.exists():
        raise FileExistsError(progress_path)
    save(progress_path, progress.record(time.monotonic(), 'starting'))
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=True, bufsize=0)
    timed_out = False
    next_report = 0.0
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                now = time.monotonic()
                if progress.expired(now):
                    timed_out = True
                    stop_owned(process, grace)
                    break
                events = selector.select(min(1, seconds - (now - progress.changed)))
                for key, _ in events:
                    chunk = os.read(key.fd, 65536)
                    if chunk:
                        output.write(chunk)
                        output.flush()
                        progress.feed(chunk, time.monotonic())
                    else:
                        selector.unregister(key.fileobj)
                now = time.monotonic()
                if now >= next_report:
                    save(progress_path, progress.record(now))
                    next_report = now + 5
                if not selector.get_map() and process.poll() is not None:
                    break
        code = process.wait()
        code = 124 if timed_out else (code if code >= 0 else 128 - code)
        # Missing progress must not turn a wrong/quiet executable into evidence
        # of a successful proof check. The caller also pins checker + arguments.
        if code == 0 and progress.count == 0:
            code = 65
        phase = 'passed' if code == 0 else ('timeout' if timed_out else 'failed')
        record = progress.record(time.monotonic(), phase, exit_code=code,
                                 command=command, timeout_scope='declaration-progress')
        save(progress_path, record)
        return record
    except BaseException:
        stop_owned(process, grace)
        save(progress_path, progress.record(time.monotonic(), 'interrupted'))
        raise
    finally:
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module', required=True)
    parser.add_argument('--seconds', required=True, type=float)
    parser.add_argument('--progress', required=True, type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('Missing checker command')

    def interrupted(signum, _frame):
        raise InterruptedError(f'Received signal {signum}')

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, interrupted)
    return run(command, args.module, args.seconds, args.progress, sys.stdout.buffer)['exit_code']


if __name__ == '__main__':
    raise SystemExit(main())
