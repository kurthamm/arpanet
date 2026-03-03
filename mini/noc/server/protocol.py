"""Client connection handling and JSON protocol implementation."""

import os
import socket
import selectors
import json
import time
from typing import Dict, List, Set, Optional, Callable, Any, TYPE_CHECKING

from ..protocol import (
    ProcessState, encode_message, decode_message,
    ok_response, error_response, event_message,
    CMD_STATUS, CMD_HISTORY, CMD_LIGHTS, CMD_CONT, CMD_RESET, CMD_REBOOT,
    CMD_RESTART, CMD_STOP, CMD_START, CMD_ATTACH, CMD_DETACH,
    CMD_SUBSCRIBE, CMD_UNSUBSCRIBE, CMD_QUIT, CMD_INPUT,
    EventType,
)

if TYPE_CHECKING:
    from .imp import IMPController
    from .ncp import NCPController


class ClientConnection:
    """A single client connection."""

    def __init__(self, sock: socket.socket, addr: str, client_id: str):
        self.sock = sock
        self.addr = addr
        self.client_id = client_id
        self.subscriptions: Set[str] = set()
        self.attached_imp: Optional[int] = None
        self.recv_buffer = b""
        self.send_buffer = b""

    def fileno(self) -> int:
        return self.sock.fileno()


class ClientHandler:
    """Handles client connections and protocol messages."""

    def __init__(
        self,
        loop,
        socket_path: str,
        imps: Dict[int, 'IMPController'],
        ncps: Dict[int, 'NCPController'],
        on_quit: Optional[Callable[[], None]] = None,
    ):
        self.loop = loop
        self.socket_path = socket_path
        self.imps = imps
        self.ncps = ncps
        self.on_quit = on_quit

        self._clients: Dict[int, ClientConnection] = {}  # fd -> client
        self._client_counter = 0
        self._server_socket: Optional[socket.socket] = None

    def start(self):
        """Start listening for client connections."""
        # Remove stale socket file
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass

        self._server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._server_socket.bind(self.socket_path)
        self._server_socket.listen(16)
        self._server_socket.setblocking(False)

        # Make socket accessible
        os.chmod(self.socket_path, 0o666)

        self.loop.register(
            self._server_socket.fileno(),
            selectors.EVENT_READ,
            self._accept_connection
        )

    def stop(self):
        """Stop accepting connections and close all clients."""
        if self._server_socket:
            self.loop.unregister(self._server_socket.fileno())
            self._server_socket.close()
            try:
                os.unlink(self.socket_path)
            except:
                pass

        for client in list(self._clients.values()):
            self._close_client(client)

    def broadcast_event(self, event_type: str, **kwargs):
        """Broadcast an event to subscribed clients."""
        msg = event_message(event_type, **kwargs)

        for client in self._clients.values():
            if event_type in client.subscriptions or "all" in client.subscriptions:
                self._send_message(client, msg)

    def _accept_connection(self, fd: int, events: int):
        """Accept a new client connection."""
        try:
            sock, addr = self._server_socket.accept()
            sock.setblocking(False)

            self._client_counter += 1
            client_id = f"client-{self._client_counter}"

            client = ClientConnection(sock, str(addr), client_id)
            self._clients[sock.fileno()] = client

            self.loop.register(
                sock.fileno(),
                selectors.EVENT_READ,
                self._handle_client_event
            )
        except Exception as e:
            print(f"Error accepting connection: {e}")

    def _handle_client_event(self, fd: int, events: int):
        """Handle events on a client socket."""
        client = self._clients.get(fd)
        if not client:
            return

        if events & selectors.EVENT_READ:
            self._handle_client_read(client)

        if events & selectors.EVENT_WRITE:
            self._handle_client_write(client)

    def _handle_client_read(self, client: ClientConnection):
        """Handle readable client socket."""
        try:
            data = client.sock.recv(4096)
            if not data:
                self._close_client(client)
                return

            client.recv_buffer += data

            # Process complete lines
            while b'\n' in client.recv_buffer:
                line, client.recv_buffer = client.recv_buffer.split(b'\n', 1)
                self._process_message(client, line)

        except (ConnectionResetError, BrokenPipeError):
            self._close_client(client)
        except Exception as e:
            print(f"Error reading from client: {e}")
            self._close_client(client)

    def _handle_client_write(self, client: ClientConnection):
        """Handle writable client socket."""
        if not client.send_buffer:
            # Nothing to write, stop watching for write events
            self.loop.modify(client.fileno(), selectors.EVENT_READ)
            return

        try:
            sent = client.sock.send(client.send_buffer)
            client.send_buffer = client.send_buffer[sent:]

            if not client.send_buffer:
                self.loop.modify(client.fileno(), selectors.EVENT_READ)

        except (ConnectionResetError, BrokenPipeError):
            self._close_client(client)

    def _send_message(self, client: ClientConnection, msg: Dict[str, Any]):
        """Send a message to a client."""
        data = encode_message(msg)
        client.send_buffer += data

        # Enable write events
        try:
            self.loop.modify(
                client.fileno(),
                selectors.EVENT_READ | selectors.EVENT_WRITE
            )
        except:
            pass

    def _close_client(self, client: ClientConnection):
        """Close a client connection."""
        # Detach from any IMP
        if client.attached_imp is not None:
            imp = self.imps.get(client.attached_imp)
            if imp:
                imp.detach(client.client_id)

        # Unregister and close
        try:
            self.loop.unregister(client.fileno())
        except:
            pass

        try:
            client.sock.close()
        except:
            pass

        self._clients.pop(client.fileno(), None)

    def _process_message(self, client: ClientConnection, line: bytes):
        """Process a JSON message from a client."""
        msg = decode_message(line)
        if msg is None:
            self._send_message(client, error_response("Invalid JSON"))
            return

        cmd = msg.get("cmd")
        if not cmd:
            self._send_message(client, error_response("Missing 'cmd' field"))
            return

        # Dispatch command
        handler = {
            CMD_STATUS: self._cmd_status,
            CMD_HISTORY: self._cmd_history,
            CMD_LIGHTS: self._cmd_lights,
            CMD_CONT: self._cmd_cont,
            CMD_RESET: self._cmd_reset,
            CMD_REBOOT: self._cmd_reset,  # Alias for reset
            CMD_RESTART: self._cmd_restart,
            CMD_STOP: self._cmd_stop,
            CMD_START: self._cmd_start,
            CMD_ATTACH: self._cmd_attach,
            CMD_DETACH: self._cmd_detach,
            CMD_SUBSCRIBE: self._cmd_subscribe,
            CMD_UNSUBSCRIBE: self._cmd_unsubscribe,
            CMD_QUIT: self._cmd_quit,
            CMD_INPUT: self._cmd_input,
        }.get(cmd)

        if handler is None:
            self._send_message(client, error_response(f"Unknown command: {cmd}"))
            return

        try:
            response = handler(client, msg)
            self._send_message(client, response)
        except Exception as e:
            self._send_message(client, error_response(str(e)))

    def _resolve_imp_target(self, target: str) -> Optional['IMPController']:
        """Resolve a target string to an IMP controller."""
        # Try as number
        try:
            num = int(target)
            if num in self.imps:
                return self.imps[num]
        except ValueError:
            pass

        # Try as name
        target_lower = target.lower()
        for imp in self.imps.values():
            if imp.config.name.lower() == target_lower:
                return imp

        return None

    def _resolve_targets(self, target: str) -> List['IMPController']:
        """Resolve target specifier to list of IMPs.

        Target can be:
        - Single: "5", "UCLA"
        - Multiple: "1,2,5"
        - Groups: "all", "halted", "crashed", "running", "stopped"
        """
        if target == "all":
            return list(self.imps.values())
        elif target == "halted":
            return [i for i in self.imps.values() if i.state == ProcessState.HALTED]
        elif target == "crashed":
            return [i for i in self.imps.values() if i.state == ProcessState.CRASHED]
        elif target == "running":
            return [i for i in self.imps.values() if i.state == ProcessState.RUNNING]
        elif target == "stopped":
            return [i for i in self.imps.values() if i.state == ProcessState.STOPPED]
        elif "," in target:
            # Multiple targets
            results = []
            for t in target.split(","):
                imp = self._resolve_imp_target(t.strip())
                if imp:
                    results.append(imp)
            return results
        else:
            # Single target
            imp = self._resolve_imp_target(target)
            return [imp] if imp else []

    # Command handlers

    def _cmd_status(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle status command."""
        target = msg.get("target")

        if target:
            imp = self._resolve_imp_target(target)
            if imp:
                return ok_response({"imp": imp.get_status().to_dict()})

            # Check NCPs
            try:
                ncp_num = int(target)
                if ncp_num in self.ncps:
                    return ok_response({"ncp": self.ncps[ncp_num].get_status().to_dict()})
            except ValueError:
                pass

            return error_response(f"Target '{target}' not found")

        # Full status
        return ok_response({
            "imps": [i.get_status().to_dict() for i in sorted(self.imps.values(), key=lambda x: x.config.number)],
            "ncps": [n.get_status().to_dict() for n in sorted(self.ncps.values(), key=lambda x: x.config.full_host)],
        })

    def _cmd_history(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle history command."""
        target = msg.get("target")
        if not target:
            return error_response("Missing 'target' parameter")

        imp = self._resolve_imp_target(target)
        if not imp:
            return error_response(f"IMP '{target}' not found")

        limit = msg.get("limit", 20)
        history = imp.get_history(limit)

        return ok_response({
            "imp": imp.config.number,
            "name": imp.config.name,
            "history": [h.to_dict() for h in history],
        })

    def _cmd_lights(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle lights command."""
        target = msg.get("target")

        if target:
            imp = self._resolve_imp_target(target)
            if not imp:
                return error_response(f"IMP '{target}' not found")

            # Show lights only when RUNNING, otherwise show state
            if imp.state == ProcessState.RUNNING:
                display_value = imp.lights
            else:
                display_value = imp.state.value

            return ok_response({
                "imp": imp.config.number,
                "name": imp.config.name,
                "lights": display_value,
                "state": imp.state.value,
                "timestamp": imp.lights_timestamp,
            })

        # All IMPs
        lights = {}
        for imp in self.imps.values():
            # Show lights only when RUNNING, otherwise show state
            if imp.state == ProcessState.RUNNING:
                display_value = imp.lights
            else:
                display_value = imp.state.value

            lights[imp.config.number] = {
                "name": imp.config.name,
                "lights": display_value,
                "state": imp.state.value,
                "timestamp": imp.lights_timestamp,
            }

        return ok_response({"lights": lights})

    def _cmd_cont(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle cont command."""
        target = msg.get("target", "halted")
        imps = self._resolve_targets(target)

        if not imps:
            return error_response(f"No IMPs matched target '{target}'")

        continued = []
        for imp in imps:
            if imp.state == ProcessState.HALTED:
                imp.send_cont()
                continued.append(imp.config.number)

        return ok_response({"continued": continued})

    def _cmd_reset(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle reset command."""
        target = msg.get("target")
        if not target:
            return error_response("Missing 'target' parameter")

        imps = self._resolve_targets(target)
        if not imps:
            return error_response(f"No IMPs matched target '{target}'")

        reset = []
        for imp in imps:
            if imp.state == ProcessState.HALTED:
                imp.send_reset()
                reset.append(imp.config.number)

        return ok_response({"reset": reset})

    def _cmd_restart(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle restart command."""
        target = msg.get("target")
        if not target:
            return error_response("Missing 'target' parameter")

        imps = self._resolve_targets(target)
        if not imps:
            return error_response(f"No IMPs matched target '{target}'")

        restarted = []
        for imp in imps:
            imp.force_restart()
            restarted.append(imp.config.number)

        return ok_response({"restarted": restarted})

    def _cmd_stop(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle stop command."""
        target = msg.get("target")
        if not target:
            return error_response("Missing 'target' parameter")

        imps = self._resolve_targets(target)
        if not imps:
            return error_response(f"No IMPs matched target '{target}'")

        stopped = []
        for imp in imps:
            if imp.state != ProcessState.STOPPED:
                imp.stop()
                stopped.append(imp.config.number)

        return ok_response({"stopped": stopped})

    def _cmd_start(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle start command."""
        target = msg.get("target")
        if not target:
            return error_response("Missing 'target' parameter")

        imps = self._resolve_targets(target)
        if not imps:
            return error_response(f"No IMPs matched target '{target}'")

        started = []
        for imp in imps:
            if imp.state == ProcessState.STOPPED:
                imp.start()
                started.append(imp.config.number)

        return ok_response({"started": started})

    def _cmd_attach(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle attach command."""
        target = msg.get("target")
        if not target:
            return error_response("Missing 'target' parameter")

        imp = self._resolve_imp_target(target)
        if not imp:
            return error_response(f"IMP '{target}' not found")

        # Callback to forward output to client
        def output_callback(data: bytes):
            self._send_message(client, {
                "event": "output",
                "imp": imp.config.number,
                "data": data.decode('utf-8', errors='replace'),
            })

        if not imp.attach(client.client_id, output_callback):
            return error_response(f"IMP {imp.config.number} already attached by {imp.attached_client}")

        client.attached_imp = imp.config.number

        return ok_response({
            "attached": imp.config.number,
            "name": imp.config.name,
        })

    def _cmd_detach(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle detach command."""
        if client.attached_imp is None:
            return error_response("Not attached to any IMP")

        imp = self.imps.get(client.attached_imp)
        if imp:
            imp.detach(client.client_id)

        detached = client.attached_imp
        client.attached_imp = None

        return ok_response({"detached": detached})

    def _cmd_subscribe(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle subscribe command."""
        events = msg.get("events", ["all"])
        if isinstance(events, str):
            events = [events]

        for event in events:
            client.subscriptions.add(event)

        return ok_response({"subscribed": list(client.subscriptions)})

    def _cmd_unsubscribe(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle unsubscribe command."""
        events = msg.get("events", [])
        if isinstance(events, str):
            events = [events]

        for event in events:
            client.subscriptions.discard(event)

        return ok_response({"subscribed": list(client.subscriptions)})

    def _cmd_quit(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle quit command - graceful server shutdown."""
        if self.on_quit:
            self.on_quit()
        return ok_response({"message": "Shutting down..."})

    def _cmd_input(self, client: ClientConnection, msg: Dict) -> Dict:
        """Handle input command - send raw input to attached IMP."""
        if client.attached_imp is None:
            return error_response("Not attached to any IMP")

        data = msg.get("data", "")
        imp = self.imps.get(client.attached_imp)
        if imp:
            imp.write(data.encode('utf-8'))

        return ok_response({})
