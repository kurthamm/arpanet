#!/usr/bin/env python3
# Persistent line drainer: holds a TCP connection to a sim telnet line OPEN and
# continuously reads (so the monitor's output buffer never fills -> no tyhngu hang).
# Unlike `nc </dev/null` (which drops on stdin EOF and reconnects in a loop, leaving
# the line mostly disconnected), this keeps ONE connection open for the sim's life.
import socket, sys, time, subprocess
port = int(sys.argv[1])
logpath = sys.argv[2]
log = open(logpath, "ab", 0)

def ki_alive():
    return subprocess.run(["pgrep", "-x", "pdp10-ki"], capture_output=True).returncode == 0

s = None
# wait for the port to come up
for _ in range(120):
    if not ki_alive() and s is None:
        pass
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=2)
        s.settimeout(5)
        log.write(b"[drain %d connected]\n" % port)
        break
    except OSError:
        time.sleep(0.5)
if s is None:
    log.write(b"[drain %d: never connected]\n" % port)
    sys.exit(1)

while ki_alive():
    try:
        d = s.recv(4096)
        if d:
            log.write(d)
        else:
            # peer closed; reconnect
            try: s.close()
            except OSError: pass
            s = None
            for _ in range(60):
                try:
                    s = socket.create_connection(("127.0.0.1", port), timeout=2)
                    s.settimeout(5); break
                except OSError:
                    if not ki_alive(): break
                    time.sleep(0.5)
            if s is None: break
    except socket.timeout:
        continue            # no data is fine — KEEP the connection open (the point)
    except OSError:
        try: s.close()
        except OSError: pass
        s = None
        time.sleep(0.3)
        if not ki_alive(): break
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=2); s.settimeout(5)
        except OSError:
            break
log.write(b"\n[drain %d exit]\n" % port)
