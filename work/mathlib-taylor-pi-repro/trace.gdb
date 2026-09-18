set pagination off
set confirm off
set disable-randomization off
set print thread-events off
set auto-load off
handle SIGUSR1 stop print nopass
handle SIGALRM stop print pass
handle SIGPIPE nostop noprint pass
python
import collections
import gdb
import os
import signal
import threading
import time

done = threading.Event()
started = False

def tick(pid):
    while not done.wait(60):
        try:
            os.kill(pid, signal.SIGUSR1)
        except ProcessLookupError:
            break

def on_continue(event):
    global started
    if not started:
        started = True
        threading.Thread(target=tick, args=(gdb.selected_inferior().pid,), daemon=True).start()

def snapshot(event):
    if not isinstance(event, gdb.SignalEvent) or event.stop_signal not in ('SIGUSR1', 'SIGALRM'):
        return
    frames = []
    frame = gdb.newest_frame()
    while frame is not None and len(frames) < 10000:
        frames.append(frame.name() or '?')
        frame = frame.older()
    gdb.write('\n[sample %.3f] depth=%d truncated=%s\n' % (time.time(), len(frames), frame is not None))
    gdb.write('counts=%s\n' % collections.Counter(frames).most_common(12))
    for index, name in enumerate(frames):
        if index < 12 or index >= len(frames) - 65 or 'Conversion' in name:
            gdb.write('#%d %s\n' % (index, name))
    gdb.execute('continue')

gdb.events.cont.connect(on_continue)
gdb.events.stop.connect(snapshot)
gdb.events.exited.connect(lambda event: done.set())
end
run
