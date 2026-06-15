#!/usr/bin/env python3
"""Line-mode UCLA-CCN front door for host #65."""

from __future__ import annotations

import argparse
import os
import queue
import re
import selectors
import signal
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path


DEFAULT_PORT = 16515
DEFAULT_HERCULES_PORT = 3271
MAX_SESSIONS = 8
MAX_TSO_SESSIONS = 1


HELP_TEXT = """\
SERVICE-DESCRIPTION
RJS EBCDIC REMOTE JOB SERVICE
ARJS ASCII REMOTE JOB SERVICE
TTYRJS TELETYPE REMOTE JOB SERVICE
BBOARD BULLETIN BOARD
TSO ACCESS TO IBM TSO TIME SHARING SYSTEM
HELP PRODUCES THIS INFORMATION
LOGOFF CLOSES THIS CONNECTION
"""

BBOARD_TEXT = """\
UCLA CCN BULLETIN BOARD

ICCC VISITOR NOTE:
THIS HOST IS UCLA-CCN, ARPANET HOST #65 / OCTAL #101, ATTACHED TO UCLA IMP #1.

THE 360/91 TSO PATH IS BACKED BY A REAL OS/360 MVT, TCAM, AND TSO SESSION
UNDER HERCULES. THE PUBLIC BRIDGE IS LINE-MODE; THE BACKEND TERMINAL IS
OPERATED WITH 3270 CONTROL SEQUENCES.
"""


def s3270_quote(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def send_line(conn: socket.socket, text: str = "") -> None:
    conn.sendall(text.encode("ascii", "replace") + b"\r\n")


def send_block(conn: socket.socket, text: str) -> None:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    conn.sendall(normalized.replace("\n", "\r\n").encode("ascii", "replace"))


def read_line(conn: socket.socket, *, strip: bool = True) -> str | None:
    data = bytearray()
    while True:
        chunk = conn.recv(1)
        if not chunk:
            return None if not data else data.decode("ascii", "ignore")
        if chunk in (b"\r", b"\n"):
            line = data.decode("ascii", "ignore")
            return line.strip() if strip else line.rstrip("\r\n")
        if chunk == b"\x7f":
            if data:
                data.pop()
            continue
        data.extend(chunk)


class S3270Process:
    def __init__(self, port: int, transcript: Path | None = None) -> None:
        self.port = port
        self.transcript = transcript
        self.proc = subprocess.Popen(
            ["s3270", "-script"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self.output: queue.Queue[str] = queue.Queue()
        self.reader = threading.Thread(target=self._read_output, daemon=True)
        self.reader.start()

    def _read_output(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            if self.transcript is not None:
                with self.transcript.open("a", encoding="utf-8") as log:
                    log.write(line)
            self.output.put(line.rstrip("\n"))

    def action(self, command: str, delay: float = 0.1) -> list[str]:
        if self.proc.poll() is not None:
            raise RuntimeError("s3270 process exited")
        assert self.proc.stdin is not None
        self.proc.stdin.write(command + "\n")
        self.proc.stdin.flush()
        time.sleep(delay)
        return self.drain()

    def drain(self, idle: float = 0.15, limit: float = 2.0) -> list[str]:
        lines: list[str] = []
        deadline = time.monotonic() + limit
        while time.monotonic() < deadline:
            try:
                line = self.output.get(timeout=idle)
            except queue.Empty:
                if lines:
                    break
                continue
            lines.append(line)
        return lines

    def connect(self) -> None:
        self.action(f"Connect(127.0.0.1:{self.port})", delay=0.5)

    def screen(self) -> str:
        lines = self.action("Ascii()", delay=0.3)
        data = [line[6:].rstrip() for line in lines if line.startswith("data: ")]
        return "\n".join(data).rstrip()

    def quit(self) -> None:
        try:
            self.action("Quit()", delay=0.1)
        except Exception:
            pass
        try:
            self.proc.terminate()
            self.proc.wait(timeout=2)
        except Exception:
            self.proc.kill()


class TSOBridge:
    def __init__(self, hercules_port: int, transcript_dir: Path) -> None:
        self.hercules_port = hercules_port
        self.transcript_dir = transcript_dir
        timestamp = int(time.time() * 1000)
        self.keeper = S3270Process(hercules_port, transcript_dir / f"public-tso-keeper-{timestamp}.txt")
        self.term = S3270Process(hercules_port, transcript_dir / f"public-tso-session-{timestamp}.txt")
        self.logged_in = False
        self.force_edit_command = False

    def start(self) -> str:
        self.keeper.connect()
        time.sleep(1.0)
        self.term.connect()
        time.sleep(0.5)
        screen = self.reset_to_logon()
        if "IKJ54012A ENTER LOGON" not in screen:
            raise RuntimeError("TSO terminal line is not at the LOGON prompt; operator restart required")
        return screen

    def reset_to_logon(self) -> str:
        for _attempt in range(3):
            self.term.action("Clear()", delay=1.0)
            time.sleep(1.0)
            screen = self.term.screen()
            if "IKJ54012A ENTER LOGON" in screen:
                self.logged_in = False
                return screen
            if re.search(r"(^|\n)\s*READY\s*($|\n)", screen):
                self.term.action("Home()", delay=0.1)
                self.term.action('String("LOGOFF")', delay=0.1)
                self.term.action("EraseEOF()", delay=0.1)
                self.term.action("Enter()", delay=2.0)
                time.sleep(1.0)
                continue
            if self._looks_active(screen):
                self.term.action("PA(1)", delay=1.0)
                time.sleep(1.0)
                screen = self._leave_edit_if_needed(self.term.screen())
                if re.search(r"(^|\n)\s*READY\s*($|\n)", screen):
                    self.term.action("Home()", delay=0.1)
                    self.term.action('String("LOGOFF")', delay=0.1)
                    self.term.action("EraseEOF()", delay=0.1)
                    self.term.action("Enter()", delay=2.0)
                    time.sleep(1.0)
                continue
        return self.term.screen()

    @staticmethod
    def _looks_active(screen: str) -> bool:
        return (
            re.search(r"(^|\n)\s*READY\s*($|\n)", screen) is not None
            or re.search(r"(^|\n)\s*EDIT\s*($|\n)", screen) is not None
            or " INPUT" in screen
            or "ENTER DATA SET TYPE" in screen
            or "REENTER -" in screen
        )

    @staticmethod
    def _last_nonblank(screen: str) -> str:
        for line in reversed(screen.splitlines()):
            stripped = line.strip()
            if stripped:
                return stripped
        return ""

    @classmethod
    def _at_edit_command_prompt(cls, screen: str) -> bool:
        # The 3270 screen often retains scrollback, so do not search the
        # entire screen for EDIT. Only the active prompt line is meaningful.
        last = cls._last_nonblank(screen)
        if last == "EDIT":
            return True
        # After SAVE, TSO EDIT can leave "***" as the last visible line while
        # the active command field is still the EDIT prompt. READY means the
        # retained EDIT text is only scrollback, so do not force HOME there.
        return (
            last == "***"
            and re.search(r"(^|\n)\s*EDIT\s*($|\n)", screen) is not None
            and re.search(r"(^|\n)\s*READY\s*($|\n)", screen) is None
        )

    @classmethod
    def _at_screen_hold(cls, screen: str) -> bool:
        return cls._last_nonblank(screen) == "***"

    def _clear_screen_hold_if_needed(self, screen: str) -> str:
        # TSO uses *** as a real output hold. The next Enter dismisses that
        # held screen; sending a command before doing so loses the command.
        for _attempt in range(3):
            if not self._at_screen_hold(screen):
                break
            self.term.action("Enter()", delay=1.0)
            time.sleep(0.5)
            screen = self.term.screen()
        return screen

    def _leave_edit_if_needed(self, screen: str) -> str:
        if " INPUT" in screen:
            self.term.action("Enter()", delay=1.0)
            time.sleep(0.5)
            screen = self.term.screen()
        if re.search(r"(^|\n)\s*EDIT\s*($|\n)", screen):
            self.term.action("Home()", delay=0.1)
            self.term.action('String("END")', delay=0.1)
            self.term.action("EraseEOF()", delay=0.1)
            self.term.action("Enter()", delay=1.5)
            time.sleep(0.5)
            screen = self.term.screen()
        return screen

    def _send_edit_command(self, command: str) -> str:
        self.term.action("Home()", delay=0.1)
        self.term.action("EraseEOF()", delay=0.1)
        self.term.action(f'String("{s3270_quote(command)}")', delay=0.1)
        self.term.action("EraseEOF()", delay=0.1)
        self.term.action("Enter()", delay=1.5)
        time.sleep(1.0)
        return self.term.screen()

    def submit(self, line: str) -> str:
        command = line.rstrip("\r\n")
        upper_command = command.strip().upper()
        if not command.strip():
            self.term.action("Enter()", delay=1.0)
            time.sleep(0.5)
            return self.term.screen()
        screen = self._clear_screen_hold_if_needed(self.term.screen())
        if "IKJ54012A ENTER LOGON" in screen and not self.logged_in:
            self.term.action("Home()", delay=0.1)
            self.term.action(f'String("{s3270_quote(command)}")', delay=0.1)
            self.term.action("EraseEOF()", delay=0.1)
        else:
            if self.force_edit_command and upper_command not in {"SAVE", "END"}:
                preflight = self._send_edit_command("END")
                if re.search(r"(^|\n)\s*READY\s*($|\n)", preflight):
                    self.force_edit_command = False
                    screen = preflight
                else:
                    return preflight
            # TSO command screens leave the cursor at the next input field. Moving
            # HOME there can land in protected scrollback text and split commands.
            # EDIT subcommand mode is the exception: HOME reaches the command field.
            in_edit_command = (
                " INPUT" not in screen
                and (
                    self.force_edit_command
                    or
                    self._at_edit_command_prompt(screen)
                    or (
                        upper_command == "END"
                        and re.search(r"(^|\n)\s*READY\s*($|\n)", screen) is None
                    )
                )
            )
            if in_edit_command:
                result = self._send_edit_command(command)
                if re.search(r"(^|\n)\s*READY\s*($|\n)", result):
                    self.logged_in = True
                    self.force_edit_command = False
                elif re.search(r"(^|\n)\s*SAVED\s*($|\n)", result):
                    self.force_edit_command = True
                return result
            self.term.action(f'String("{s3270_quote(command)}")', delay=0.1)
        self.term.action("Enter()", delay=1.5)
        time.sleep(1.0)
        result = self.term.screen()
        if re.search(r"(^|\n)\s*READY\s*($|\n)", result):
            self.logged_in = True
            self.force_edit_command = False
        elif re.search(r"(^|\n)\s*SAVED\s*($|\n)", result):
            self.force_edit_command = True
        return result

    def close(self) -> None:
        try:
            self.term.action("PA(1)", delay=0.5)
            time.sleep(0.5)
            screen = self._leave_edit_if_needed(self.term.screen())
            if re.search(r"(^|\n)\s*READY\s*($|\n)", screen):
                self.term.action("Home()", delay=0.1)
                self.term.action('String("LOGOFF")', delay=0.1)
                self.term.action("EraseEOF()", delay=0.1)
                self.term.action("Enter()", delay=1.5)
                time.sleep(0.5)
        except Exception:
            pass
        self.term.quit()
        self.keeper.quit()


class FrontDoor:
    def __init__(self, host: str, port: int, ready_marker: Path, hercules_port: int, transcript_dir: Path) -> None:
        self.host = host
        self.port = port
        self.ready_marker = ready_marker
        self.hercules_port = hercules_port
        self.transcript_dir = transcript_dir
        self.stop_event = threading.Event()
        self.session_lock = threading.Lock()
        self.tso_lock = threading.Lock()
        self.session_count = 0
        self.tso_session_count = 0

    def tso_ready(self) -> bool:
        return self.ready_marker.exists()

    def serve(self) -> None:
        signal.signal(signal.SIGTERM, lambda _sig, _frame: self.stop_event.set())
        signal.signal(signal.SIGINT, lambda _sig, _frame: self.stop_event.set())

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind((self.host, self.port))
            srv.listen()
            srv.setblocking(False)
            selector = selectors.DefaultSelector()
            selector.register(srv, selectors.EVENT_READ)

            while not self.stop_event.is_set():
                for key, _mask in selector.select(timeout=0.5):
                    conn, _addr = key.fileobj.accept()
                    conn.settimeout(300)
                    thread = threading.Thread(target=self.handle_client, args=(conn,), daemon=True)
                    thread.start()

    def handle_client(self, conn: socket.socket) -> None:
        with conn:
            with self.session_lock:
                if self.session_count >= MAX_SESSIONS:
                    send_line(conn, "UCLA-CCN IS FULL; TRY AGAIN SHORTLY.")
                    return
                self.session_count += 1
            try:
                self.session(conn)
            finally:
                with self.session_lock:
                    self.session_count -= 1

    def session(self, conn: socket.socket) -> None:
        send_line(conn, "UCLA CCN 360/91 SERVER TELNET.")
        send_line(conn, "VERSION 2.5 30 APR 1972")
        send_line(conn, "ENTER COMMAND OR 'HELP':")

        while True:
            conn.sendall(b"* ")
            line = read_line(conn)
            if line is None:
                return
            command = line.strip().upper()
            if not command:
                continue
            if command == "HELP":
                send_block(conn, HELP_TEXT)
            elif command == "BBOARD":
                send_block(conn, BBOARD_TEXT)
            elif command == "TSO":
                if self.tso_ready():
                    self.tso_session(conn)
                    return
                else:
                    send_line(conn, "TSO IS NOT PUBLIC-READY ON THIS HOST.")
                    send_line(conn, "REAL MVT/TCAM/TSO VALIDATION HAS NOT PASSED.")
            elif command in {"LOGOFF", "BYE", "QUIT", "OFF"}:
                send_line(conn, "UCLA CCN LOGOFF COMPLETE.")
                return
            else:
                send_line(conn, "UNKNOWN COMMAND. TYPE HELP.")

    def tso_session(self, conn: socket.socket) -> None:
        if not self.tso_lock.acquire(blocking=False):
            send_line(conn, "UCLA-CCN TSO IS BUSY; TRY AGAIN SHORTLY.")
            return
        bridge: TSOBridge | None = None
        try:
            self.tso_session_count += 1
            if self.tso_session_count > MAX_TSO_SESSIONS:
                send_line(conn, "UCLA-CCN TSO IS FULL; TRY AGAIN SHORTLY.")
                return
            self.transcript_dir.mkdir(parents=True, exist_ok=True)
            send_line(conn, "CONNECTING TO UCLA-CCN OS/360 MVT TSO.")
            send_line(conn, "TYPE LOGON IBMUSER AT THE TSO LOGON PROMPT.")
            bridge = TSOBridge(self.hercules_port, self.transcript_dir)
            screen = bridge.start()
            send_block(conn, screen + "\n")
            while True:
                conn.sendall(b"TSO> ")
                line = read_line(conn, strip=False)
                if line is None:
                    return
                command = line.rstrip("\r\n")
                if command.upper() in {"QUIT", "BYE", "OFF"}:
                    send_line(conn, "UCLA-CCN TSO SESSION CLOSED.")
                    return
                screen = bridge.submit(command)
                send_block(conn, screen + "\n")
                if command.upper() == "LOGOFF" and "LOGGED OFF TSO" in screen:
                    send_line(conn, "UCLA-CCN TSO SESSION CLOSED.")
                    return
        except Exception as exc:
            send_line(conn, f"UCLA-CCN TSO BRIDGE ERROR: {exc}")
        finally:
            if bridge is not None:
                bridge.close()
            self.tso_session_count -= 1
            self.tso_lock.release()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--hercules-port", type=int, default=DEFAULT_HERCULES_PORT)
    parser.add_argument(
        "--transcript-dir",
        default=os.path.join(os.path.dirname(__file__), "transcripts"),
    )
    parser.add_argument(
        "--ready-marker",
        default=os.path.join(os.path.dirname(__file__), "runtime", "TSO_READY"),
    )
    args = parser.parse_args()

    frontdoor = FrontDoor(
        args.host,
        args.port,
        Path(args.ready_marker),
        args.hercules_port,
        Path(args.transcript_dir),
    )
    frontdoor.serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
