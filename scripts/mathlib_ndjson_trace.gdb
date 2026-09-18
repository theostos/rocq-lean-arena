set pagination off
set confirm off
set disable-randomization off
set print thread-events off
set auto-load off
handle SIGUSR1 stop print nopass
handle SIGALRM stop print pass
handle SIGPIPE nostop noprint pass
python
import gdb
import time

def snapshot(event):
    if isinstance(event, gdb.SignalEvent) and event.stop_signal in ("SIGUSR1", "SIGALRM"):
        gdb.write("\n[diagnostic stack] %s time=%.3f\n" % (event.stop_signal, time.time()))
        gdb.execute("thread apply all bt 80")
        gdb.execute("continue")

gdb.events.stop.connect(snapshot)
end
run
