"""Client connection to NOC server."""

import socket
import select
import json
from typing import Optional, Dict, Any, Iterator, Callable, List

from ..protocol import encode_message, decode_message


class NOCConnection:
    """Connection to the NOC server."""

    def __init__(self, socket_path: str = "/tmp/noc.sock"):
        self.socket_path = socket_path
        self._sock: Optional[socket.socket] = None
        self._recv_buffer = b""
        self._event_buffer: List[Dict[str, Any]] = []  # Events received during command/response

    def connect(self) -> bool:
        """Connect to the server. Returns True on success."""
        try:
            self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self._sock.connect(self.socket_path)
            self._sock.setblocking(False)
            return True
        except (FileNotFoundError, ConnectionRefusedError) as e:
            self._sock = None
            return False

    def disconnect(self):
        """Disconnect from the server."""
        if self._sock:
            try:
                self._sock.close()
            except:
                pass
            self._sock = None

    def is_connected(self) -> bool:
        """Check if connected."""
        return self._sock is not None

    def send_command(self, cmd: str, **kwargs) -> Dict[str, Any]:
        """Send a command and wait for response.

        Args:
            cmd: Command name
            **kwargs: Additional command parameters

        Returns:
            Response dict
        """
        if not self._sock:
            return {"ok": False, "error": "Not connected"}

        msg = {"cmd": cmd, **kwargs}
        data = encode_message(msg)

        try:
            self._sock.sendall(data)
        except (BrokenPipeError, ConnectionResetError):
            self.disconnect()
            return {"ok": False, "error": "Connection lost"}

        # Wait for response
        return self._read_response()

    def _read_response(self, timeout: float = 5.0) -> Dict[str, Any]:
        """Read a response from the server, buffering any events."""
        deadline = None
        if timeout:
            import time
            deadline = time.time() + timeout

        while True:
            # Check if we have a complete line
            while b'\n' in self._recv_buffer:
                line, self._recv_buffer = self._recv_buffer.split(b'\n', 1)
                msg = decode_message(line)
                if msg is not None:
                    # Return responses (have "ok" key)
                    if "ok" in msg:
                        return msg
                    # Buffer events for later retrieval via read_events()
                    if "event" in msg:
                        self._event_buffer.append(msg)

            # Calculate remaining timeout
            remaining = None
            if deadline:
                import time
                remaining = deadline - time.time()
                if remaining <= 0:
                    return {"ok": False, "error": "Timeout"}

            # Wait for data
            try:
                readable, _, _ = select.select([self._sock], [], [], remaining)
                if not readable:
                    return {"ok": False, "error": "Timeout"}

                data = self._sock.recv(4096)
                if not data:
                    self.disconnect()
                    return {"ok": False, "error": "Connection closed"}

                self._recv_buffer += data

            except (ConnectionResetError, BrokenPipeError):
                self.disconnect()
                return {"ok": False, "error": "Connection lost"}

    def subscribe(self, events: list) -> Dict[str, Any]:
        """Subscribe to events."""
        return self.send_command("subscribe", events=events)

    def read_events(self, timeout: float = 0.1) -> Iterator[Dict[str, Any]]:
        """Read events from the server (non-blocking generator).

        Yields event messages as they arrive.
        Raises KeyboardInterrupt if interrupted.
        """
        # First, yield any buffered events from previous command/response exchanges
        while self._event_buffer:
            yield self._event_buffer.pop(0)

        if not self._sock:
            return

        # Check for available data
        try:
            readable, _, _ = select.select([self._sock], [], [], timeout)
        except InterruptedError:
            # EINTR from signal - let KeyboardInterrupt propagate
            raise KeyboardInterrupt
        except OSError:
            return

        if readable:
            try:
                data = self._sock.recv(4096)
                if data:
                    self._recv_buffer += data
            except (OSError, ConnectionError):
                return

        # Yield complete event messages (skip responses)
        while b'\n' in self._recv_buffer:
            line, self._recv_buffer = self._recv_buffer.split(b'\n', 1)
            msg = decode_message(line)
            if msg and "event" in msg:
                yield msg
            # Messages with "ok" key are responses, skip them

    def send_input(self, data: str):
        """Send input to attached IMP (fire-and-forget)."""
        if not self._sock:
            return
        msg = {"cmd": "input", "data": data}
        try:
            self._sock.sendall(encode_message(msg))
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def attach(self, target: str) -> Dict[str, Any]:
        """Attach to an IMP for raw I/O."""
        return self.send_command("attach", target=target)

    def detach(self) -> Dict[str, Any]:
        """Detach from current IMP."""
        return self.send_command("detach")

    def fileno(self) -> int:
        """Return socket file descriptor for select()."""
        return self._sock.fileno() if self._sock else -1
