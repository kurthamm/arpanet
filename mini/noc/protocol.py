"""Shared protocol definitions for NOC client/server communication.

Wire format: Line-delimited JSON over Unix socket.
Each message is a single JSON object followed by newline.
"""

import json
from dataclasses import dataclass, asdict
from typing import Optional, List, Dict, Any, Union
from enum import Enum


class ProcessState(str, Enum):
    """State of an IMP or NCP process."""
    STOPPED = "STOPPED"      # Not running, won't auto-restart
    STARTING = "STARTING"    # Process spawned, waiting for ready signal
    RUNNING = "RUNNING"      # Fully operational
    HALTED = "HALTED"        # IMP at sim> prompt (needs 'cont')
    CRASHED = "CRASHED"      # Unexpected exit, may auto-restart


class EventType(str, Enum):
    """Event types for subscription."""
    LIGHTS = "lights"        # IMP lights changed
    STATE = "state"          # Process state changed
    OUTPUT = "output"        # Process output (for attached clients)
    RESTART = "restart"      # Process restarted


# Request commands
CMD_STATUS = "status"
CMD_HISTORY = "history"
CMD_LIGHTS = "lights"
CMD_CONT = "cont"
CMD_RESET = "reset"
CMD_REBOOT = "reboot"  # Alias for reset
CMD_RESTART = "restart"
CMD_STOP = "stop"
CMD_START = "start"
CMD_ATTACH = "attach"
CMD_DETACH = "detach"
CMD_SUBSCRIBE = "subscribe"
CMD_UNSUBSCRIBE = "unsubscribe"
CMD_QUIT = "quit"
CMD_INPUT = "input"  # Send raw input to attached process


def encode_message(msg: Dict[str, Any]) -> bytes:
    """Encode a message for transmission."""
    return (json.dumps(msg, separators=(',', ':')) + '\n').encode('utf-8')


def decode_message(line: bytes) -> Optional[Dict[str, Any]]:
    """Decode a received message line."""
    try:
        return json.loads(line.decode('utf-8').strip())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def ok_response(data: Any = None) -> Dict[str, Any]:
    """Create a success response."""
    resp = {"ok": True}
    if data is not None:
        resp["data"] = data
    return resp


def error_response(message: str) -> Dict[str, Any]:
    """Create an error response."""
    return {"ok": False, "error": message}


def event_message(event_type: str, **kwargs) -> Dict[str, Any]:
    """Create an event message."""
    return {"event": event_type, **kwargs}


@dataclass
class IMPStatus:
    """Status of a single IMP."""
    number: int
    name: str
    state: str
    pid: Optional[int]
    lights: Optional[str]
    lights_timestamp: Optional[float]
    restarts: int
    attached_client: Optional[str]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class NCPStatus:
    """Status of a single NCP daemon."""
    host: int
    name: str
    imp: int
    state: str
    pid: Optional[int]
    restarts: int

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class LightsEntry:
    """A single lights history entry."""
    value: str
    timestamp: float

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
