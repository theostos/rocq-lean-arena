set pagination off
set confirm off
set disable-randomization off
set print thread-events off
set auto-load off
set debuginfod enabled off
handle SIGUSR1 stop print nopass
handle SIGALRM stop print pass
handle SIGPIPE nostop noprint pass
python
import gdb
import os
import time

def snapshot(event):
    if isinstance(event, gdb.SignalEvent) and event.stop_signal in ("SIGUSR1", "SIGALRM"):
        started = time.monotonic()
        gdb.write("[timeout stack] signal=%s wall=%.6f\n" % (event.stop_signal, time.time()))
        gdb.execute("bt 100")
        gdb.write("[timeout stack end] stopped_seconds=%.6f\n" % (time.monotonic() - started))
        gdb.flush()
        gdb.execute("continue")

def inferior_started(event):
    pid = gdb.selected_inferior().pid
    if pid:
        gdb.write("[timeout worker] pid=%d debugger=%d\n" % (pid, os.getpid()))
        gdb.flush()
    gdb.execute("continue")

gdb.events.stop.connect(snapshot)
end
starti
python
inferior_started(None)
end
