"""Raw terminal attach mode for IMP interaction."""

import sys
import os
import tty
import termios
import select
from typing import Optional

from .connection import NOCConnection


class AttachSession:
    """Manages an attach session to an IMP.

    Press Ctrl-] to detach.
    """

    ESCAPE_CHAR = 0x1d  # Ctrl-]

    def __init__(self, conn: NOCConnection, imp_number: int, imp_name: str):
        self.conn = conn
        self.imp_number = imp_number
        self.imp_name = imp_name
        self._original_termios = None

    def run(self):
        """Run the attach session until detach."""
        if not sys.stdin.isatty():
            print("Error: stdin is not a terminal")
            return

        print(f"Attached to IMP {self.imp_number:02d} ({self.imp_name})")
        print("Press Ctrl-] to detach")
        print("-" * 40)

        # Save terminal settings
        self._original_termios = termios.tcgetattr(sys.stdin)

        try:
            # Set raw mode
            tty.setraw(sys.stdin.fileno())

            self._main_loop()

        finally:
            # Restore terminal settings
            if self._original_termios:
                termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self._original_termios)

            print()
            print("-" * 40)
            print(f"Detached from IMP {self.imp_number:02d}")

    def _main_loop(self):
        """Main I/O loop for attach session."""
        stdin_fd = sys.stdin.fileno()
        sock_fd = self.conn.fileno()

        while True:
            try:
                readable, _, _ = select.select([stdin_fd, sock_fd], [], [], 0.1)
            except OSError:
                break

            for fd in readable:
                if fd == stdin_fd:
                    # User input - read one character at a time
                    try:
                        char = os.read(stdin_fd, 1)
                    except OSError:
                        return

                    if not char:
                        return

                    # Check for escape
                    if char[0] == self.ESCAPE_CHAR:
                        self.conn.detach()
                        return

                    # Send to IMP
                    self.conn.send_input(char.decode('utf-8', errors='replace'))

                elif fd == sock_fd:
                    # Server output
                    self._handle_server_output()

    def _handle_server_output(self):
        """Handle output from the server."""
        for event in self.conn.read_events(timeout=0):
            if event.get("event") == "output":
                data = event.get("data", "")
                sys.stdout.write(data)
                sys.stdout.flush()


def attach_to_imp(conn: NOCConnection, target: str) -> bool:
    """Attach to an IMP and run interactive session.

    Returns True if session ended normally.
    """
    # Send attach command
    response = conn.attach(target)

    if not response.get("ok"):
        print(f"Error: {response.get('error', 'Unknown error')}")
        return False

    data = response.get("data", {})
    imp_number = data.get("attached")
    imp_name = data.get("name", "")

    # Print any scrollback history that was sent with the attach
    # (these events arrived before the "ok" response but were buffered)
    for event in conn.read_events(timeout=0.1):
        if event.get("event") == "output":
            print(event.get("data", ""), end="")

    # Run attach session
    session = AttachSession(conn, imp_number, imp_name)
    session.run()

    return True
