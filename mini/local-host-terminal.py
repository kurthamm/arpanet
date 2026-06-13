#!/usr/bin/env python3
"""Bridge stdin/stdout to a hosted simulator terminal line."""

import argparse
import os
import re
import select
import signal
import socket
import sys
import time

IAC = 255
SB = 250
SE = 240
BRK = 243


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


def drain_initial_output(sock, duration=1.2):
    deadline = time.monotonic() + duration
    seen = bytearray()
    while time.monotonic() < deadline:
        timeout = max(0, deadline - time.monotonic())
        readable, _, _ = select.select([sock], [], [], min(0.2, timeout))
        if sock not in readable:
            continue
        try:
            data = sock.recv(4096)
        except BlockingIOError:
            continue
        if not data:
            break
        data = strip_telnet(data)
        if data:
            seen.extend(data)
            os.write(1, data)
    return bytes(seen)


def simh_line_number(data):
    match = re.search(rb"Connected to [^\r\n]* line ([0-9]+)", data)
    if not match:
        return None
    return int(match.group(1))


def line_exceeds_limit(data, max_simh_line):
    assigned_line = simh_line_number(data)
    return assigned_line is not None and assigned_line > max_simh_line


def print_busy(host_label):
    print(
        f"\r\nHost {host_label} is busy: all visitor terminal lines are in use.\r\n"
        "Please try again in a few minutes.\r\n",
        flush=True,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("host_label")
    parser.add_argument("port", type=int)
    parser.add_argument("--connect-host", default="127.0.0.1")
    parser.add_argument(
        "--no-init",
        action="store_true",
        help="do not send the default ITS logout wakeup sequence on connect",
    )
    parser.add_argument(
        "--send-break",
        action="store_true",
        help="send a TELNET BREAK after connect",
    )
    parser.add_argument(
        "--max-simh-line",
        type=int,
        help="close with a busy message if SIMH assigns a line above this number",
    )
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
    initial_output = drain_initial_output(sock, duration=0.4)
    if args.max_simh_line is not None:
        if line_exceeds_limit(initial_output, args.max_simh_line):
            print_busy(args.host_label)
            sock.close()
            return
    if not args.no_init:
        time.sleep(0.3)
        sock.sendall(b"\x1a:LOGOUT\r\x1a\r")
    if args.send_break:
        time.sleep(0.3)
        sock.sendall(bytes((IAC, BRK)))
        initial_output += drain_initial_output(sock)
        if args.max_simh_line is not None:
            if line_exceeds_limit(initial_output, args.max_simh_line):
                print_busy(args.host_label)
                sock.close()
                return
        if b"LOGON PLEASE" not in initial_output and b"\n!" not in initial_output:
            sock.sendall(b"\r")
            initial_output += drain_initial_output(sock, duration=2.0)

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
                if args.max_simh_line is not None:
                    if line_exceeds_limit(data, args.max_simh_line):
                        os.write(1, data)
                        print_busy(args.host_label)
                        break
                os.write(1, data)

    sock.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"local hosted terminal error: {exc}", file=sys.stderr)
        sys.exit(1)
