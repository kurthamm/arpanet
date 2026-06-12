#!/usr/bin/env python3
"""Bridge stdin/stdout to a SIMH ITS simulator terminal."""

import argparse
import os
import select
import signal
import socket
import sys
import time

IAC = 255
SB = 250
SE = 240


def strip_telnet(data):
    """Remove basic telnet negotiation from SIMH's TCP terminal stream."""
    out = bytearray()
    i = 0
    while i < len(data):
        byte = data[i]
        if byte != IAC:
            if byte == 0x7F:
                i += 1
                continue
            out.append(byte)
            i += 1
            continue

        i += 1
        if i >= len(data):
            break
        command = data[i]
        i += 1

        if command == IAC:
            out.append(IAC)
        elif command == SB:
            while i < len(data):
                if data[i] == IAC and i + 1 < len(data) and data[i + 1] == SE:
                    i += 2
                    break
                i += 1
        elif command in (251, 252, 253, 254) and i < len(data):
            i += 1
    return bytes(out)


def normalize_input(data):
    return data.replace(b"\n", b"\r")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("host_label")
    parser.add_argument("port", type=int)
    parser.add_argument("--connect-host", default="127.0.0.1")
    args = parser.parse_args()

    running = True

    def stop(_signum, _frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    sock = socket.create_connection((args.connect_host, args.port), timeout=5)
    sock.setblocking(False)
    os.set_blocking(0, False)

    print(f"TELNET to host {args.host_label}.", flush=True)
    time.sleep(0.3)
    sock.sendall(b"\x1a:LOGOUT\r\x1a\r")

    while running:
        readable, _, _ = select.select([0, sock], [], [], 0.5)
        if 0 in readable:
            try:
                data = os.read(0, 4096)
            except BlockingIOError:
                data = b""
            if not data:
                break
            sock.sendall(normalize_input(data))

        if sock in readable:
            try:
                data = sock.recv(4096)
            except BlockingIOError:
                data = b""
            if not data:
                break
            data = strip_telnet(data)
            if data:
                os.write(1, data)

    sock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"local hosted terminal error: {exc}", file=sys.stderr)
        sys.exit(1)
