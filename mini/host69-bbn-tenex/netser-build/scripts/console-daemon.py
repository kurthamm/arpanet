#!/usr/bin/env python3
# Persistent scriptable console for the SIMH SCP/TENEX CTY on a telnet port.
# Holds the connection OPEN for the sim's life (so `go` never returns on EOF),
# logs everything received, and relays lines written to a control FIFO.
#   console-daemon.py <port> <fifo> <log>
# Send a command:   printf 'SYSTAT\r' > <fifo>     (use \r for CR; raw bytes ok)
import socket, sys, os, threading, time

port = int(sys.argv[1]); fifo = sys.argv[2]; logp = sys.argv[3]
if not os.path.exists(fifo):
    os.mkfifo(fifo)
log = open(logp, "ab", 0)

s = None
for _ in range(120):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=2); break
    except OSError:
        time.sleep(0.5)
if s is None:
    log.write(b"[console: never connected]\n"); sys.exit(1)
s.settimeout(1.0)
log.write(b"[console connected to %d]\n" % port)

def reader():
    while True:
        try:
            d = s.recv(4096)
            if d: log.write(d)
            elif d == b"": time.sleep(0.2)
        except socket.timeout:
            continue
        except OSError:
            break
threading.Thread(target=reader, daemon=True).start()

# Relay FIFO -> socket.  Opening a FIFO for read blocks until a writer appears,
# so reopen in a loop to accept successive commands.
while True:
    try:
        with open(fifo, "rb") as f:
            data = f.read()
        if data:
            # Interpret a trailing literal '\r'/'\n' escapes if present as bytes already.
            s.sendall(data)
            log.write(b"[sent %d bytes]\n" % len(data))
    except OSError:
        break
    time.sleep(0.1)
