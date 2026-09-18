# Saved plugin state after a partial rebuild

An isolated Rocq plugin saves a six-field tuple in `Checkpoint.vo`, then changes
its payload to seven fields. The load handler checks the tuple size before
reading it, so a stale payload produces a controlled error rather than an
unsafe memory access.

Controls: unchanged plugin; changed plugin with the same tag; changed plugin
with a new tag; rebuilt foundation with a stale checkpoint; full rebuild.
The test records actual exit codes and verifies that old `.vo` files remain
unchanged during the plugin-only tests.

```sh
python3 work/pr74-state-repro/run.py
```

Do not launch alongside another Rocq worker. `--wait-for-pid PID` waits for
the specified experiment process to exit before acquiring the shared memory
guard. Waiting uses the OS, not model polling. The test has a 1 GiB memory
budget and a ten-minute total deadline. No production files are changed.

Results: `work/pr74-state-repro/latest/results.json` and numbered `.log` files.
