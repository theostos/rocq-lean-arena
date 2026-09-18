set pagination off
set confirm off
set disable-randomization off
set print thread-events off
set auto-load off
handle SIGUSR1 stop print nopass
handle SIGPIPE nostop noprint pass
python
import gdb, os, signal, threading, time
stopped = threading.Event()
started = False
def start(event):
    global started
    if started:
        return
    pid = gdb.selected_inferior().pid
    if not pid:
        return
    started = True
    def sample():
        for _ in range(4):
            if stopped.wait(45):
                return
            try:
                os.kill(pid, signal.SIGUSR1)
            except ProcessLookupError:
                return
    threading.Thread(target=sample, daemon=True).start()
def snapshot(event):
    if isinstance(event, gdb.SignalEvent) and event.stop_signal == 'SIGUSR1':
        gdb.write('\n[diagnostic stack] time=%.3f\n' % time.time())
        gdb.execute('thread apply all bt 80')
        gdb.execute('continue')
gdb.events.cont.connect(start)
gdb.events.stop.connect(snapshot)
gdb.events.exited.connect(lambda event: stopped.set())
end
run
