"""IMP (Interface Message Processor) controller.

Manages IMP state machine, lights parsing, and history tracking.
"""

import os
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Callable, List, Dict, Any
from dataclasses import dataclass, field
from collections import deque

from ..config import IMPConfig
from ..protocol import ProcessState, IMPStatus, LightsEntry
from .process import Process, ProcessManager
from .restart import RestartPolicy


# Regex patterns for IMP output parsing
LIGHTS_PATTERN = re.compile(r'WDT LIGHTS: changed to (\d+)')
SIM_PROMPT_PATTERN = re.compile(r'^sim>', re.MULTILINE)


@dataclass
class LightsHistoryEntry:
    """A single lights history entry with timestamp."""
    value: str
    timestamp: float


class IMPController:
    """Controller for a single IMP process.

    State Machine:
        STOPPED ──[start()]──> STARTING
        STARTING ──[WDT LIGHTS]──> RUNNING
        RUNNING ──[sim>]──> HALTED
        ANY ──[exit/EOF]──> CRASHED
        CRASHED ──[restart policy]──> STARTING
        HALTED ──[cont]──> RUNNING

    Unexpected halts (entering sim> without user Ctrl-E) are logged
    to ./error-logs/ and auto-restarted.
    """

    HISTORY_SIZE = 100
    OUTPUT_SCROLLBACK = 50  # Lines of output to keep for attach context
    ERROR_LOG_DIR = "./error-logs"

    def __init__(
        self,
        config: IMPConfig,
        process_manager: ProcessManager,
        on_state_change: Optional[Callable[['IMPController', ProcessState, ProcessState], None]] = None,
        on_lights_change: Optional[Callable[['IMPController', str, float], None]] = None,
        debug_halts: bool = False,
    ):
        self.config = config
        self.process_manager = process_manager
        self.on_state_change = on_state_change
        self.on_lights_change = on_lights_change
        self.debug_halts = debug_halts

        self._state = ProcessState.STOPPED
        self._process: Optional[Process] = None
        self._lights: Optional[str] = None
        self._lights_timestamp: Optional[float] = None
        self._lights_history: deque = deque(maxlen=self.HISTORY_SIZE)
        self._output_scrollback: deque = deque(maxlen=self.OUTPUT_SCROLLBACK)
        self._restart_policy = RestartPolicy()
        self._output_buffer = b""
        self._attached_client: Optional[str] = None
        self._output_callback: Optional[Callable[[bytes], None]] = None

    def _config_script_path(self) -> str:
        """Return the SIMH script path, preferring a site-local override."""
        override = Path(self.process_manager.working_dir) / f"imp{self.config.num_str}.local.simh"
        if override.exists():
            return str(override)
        return f"./imp{self.config.num_str}.simh"

    @property
    def state(self) -> ProcessState:
        """Current IMP state."""
        return self._state

    @property
    def lights(self) -> Optional[str]:
        """Current lights value as octal string."""
        return self._lights

    @property
    def lights_timestamp(self) -> Optional[float]:
        """Timestamp of last lights change."""
        return self._lights_timestamp

    @property
    def pid(self) -> Optional[int]:
        """Process ID if running."""
        return self._process.pid if self._process else None

    @property
    def restart_count(self) -> int:
        """Number of restarts."""
        return self._restart_policy.restart_count

    @property
    def attached_client(self) -> Optional[str]:
        """ID of attached client, if any."""
        return self._attached_client

    def _set_state(self, new_state: ProcessState):
        """Change state and notify."""
        old_state = self._state
        if old_state != new_state:
            self._state = new_state
            if self.on_state_change:
                self.on_state_change(self, old_state, new_state)

    def start(self):
        """Start the IMP process."""
        if self._state not in (ProcessState.STOPPED, ProcessState.CRASHED):
            return

        self._set_state(ProcessState.STARTING)
        self._output_buffer = b""

        name = f"imp{self.config.num_str}"
        args = ["./h316ov", self._config_script_path()]

        self._process = self.process_manager.spawn(
            name=name,
            args=args,
            on_output=self._handle_output,
            on_exit=self._handle_exit,
        )

    def stop(self):
        """Stop the IMP process (no auto-restart)."""
        self._restart_policy.reset()
        self._restart_policy._restart_count = self._restart_policy.max_restarts  # Prevent restart
        if self._process:
            self.process_manager.kill(self._process)
        self._set_state(ProcessState.STOPPED)

    def send_cont(self):
        """Send 'cont' command to resume from HALTED state."""
        if self._process and self._state == ProcessState.HALTED:
            self.process_manager.write(self._process, b"cont\n")
            self._set_state(ProcessState.RUNNING)

    def send_reset(self):
        """Send reset command (reload SIMH script)."""
        if self._process and self._state == ProcessState.HALTED:
            cmd = f"do {Path(self._config_script_path()).name}\n"
            self.process_manager.write(self._process, cmd.encode())
            self._set_state(ProcessState.STARTING)
            self._output_buffer = b""

    def force_restart(self):
        """Force restart, bypassing policy."""
        self._restart_policy.reset()
        if self._process:
            self.process_manager.kill(self._process)
        # Will restart via _handle_exit

    def write(self, data: bytes):
        """Write raw data to the IMP process (for attached mode)."""
        if self._process:
            self.process_manager.write(self._process, data)

    def attach(self, client_id: str, output_callback: Callable[[bytes], None]) -> bool:
        """Attach a client for raw I/O.

        Returns True if attachment succeeded, False if already attached.
        Sends recent output history to provide context.
        """
        if self._attached_client is not None:
            return False
        self._attached_client = client_id
        self._output_callback = output_callback

        # Send scrollback history to provide context
        if self._output_scrollback and output_callback:
            history = ''.join(self._output_scrollback)
            output_callback(history.encode('utf-8', errors='replace'))

        return True

    def detach(self, client_id: str):
        """Detach a client from raw I/O."""
        if self._attached_client == client_id:
            self._attached_client = None
            self._output_callback = None

    def get_status(self) -> IMPStatus:
        """Get current status."""
        return IMPStatus(
            number=self.config.number,
            name=self.config.name,
            state=self._state.value,
            pid=self.pid,
            lights=self._lights,
            lights_timestamp=self._lights_timestamp,
            restarts=self.restart_count,
            attached_client=self._attached_client,
        )

    def get_history(self, limit: int = 20) -> List[LightsEntry]:
        """Get recent lights history."""
        entries = list(self._lights_history)[-limit:]
        return [LightsEntry(value=e.value, timestamp=e.timestamp) for e in entries]

    def _handle_output(self, data: bytes):
        """Handle output from the IMP process."""
        # Forward to attached client if any
        if self._output_callback:
            self._output_callback(data)

        # Buffer for line-based parsing
        self._output_buffer += data

        # Process complete lines
        while b'\n' in self._output_buffer:
            line, self._output_buffer = self._output_buffer.split(b'\n', 1)
            line_str = line.decode('utf-8', errors='replace')
            # Store in scrollback for attach context
            self._output_scrollback.append(line_str + '\n')
            self._process_line(line_str)

        # Check for sim> prompt (may not have newline)
        if self._output_buffer:
            text = self._output_buffer.decode('utf-8', errors='replace')
            if SIM_PROMPT_PATTERN.search(text):
                if self._state == ProcessState.RUNNING:
                    if self._attached_client is not None:
                        # User pressed Ctrl-E while attached - normal halt
                        self._set_state(ProcessState.HALTED)
                    else:
                        # Unexpected halt - log and auto-restart
                        self._handle_unexpected_halt()

    def _process_line(self, line: str):
        """Process a single line of output."""
        # Check for lights change
        match = LIGHTS_PATTERN.search(line)
        if match:
            value = match.group(1)
            timestamp = time.time()

            # Update current lights
            self._lights = value
            self._lights_timestamp = timestamp

            # Add to history
            self._lights_history.append(
                LightsHistoryEntry(value=value, timestamp=timestamp)
            )

            # Notify
            if self.on_lights_change:
                self.on_lights_change(self, value, timestamp)

            # Lights output means IMP is running
            if self._state == ProcessState.STARTING:
                self._set_state(ProcessState.RUNNING)
                self._restart_policy.record_success()
            elif self._state == ProcessState.HALTED:
                # Resumed from sim> prompt
                self._set_state(ProcessState.RUNNING)

        # Check for sim> prompt (HALTED)
        if SIM_PROMPT_PATTERN.search(line):
            if self._state == ProcessState.RUNNING:
                if self._attached_client is not None:
                    # User pressed Ctrl-E while attached - normal halt
                    self._set_state(ProcessState.HALTED)
                else:
                    # Unexpected halt - log and auto-restart
                    self._handle_unexpected_halt()

    def _save_error_log(self):
        """Save scrollback buffer to error log file.

        Creates ./error-logs/YYYYMMDD-HHMMSS-impXX.log
        """
        try:
            os.makedirs(self.ERROR_LOG_DIR, exist_ok=True)
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            filename = f"{timestamp}-imp{self.config.num_str}.log"
            filepath = os.path.join(self.ERROR_LOG_DIR, filename)

            with open(filepath, 'w') as f:
                f.write(f"IMP {self.config.number} ({self.config.name}) - Unexpected halt\n")
                f.write(f"Timestamp: {datetime.now().isoformat()}\n")
                f.write("=" * 60 + "\n\n")
                for line in self._output_scrollback:
                    f.write(line)

            print(f"[NOC] IMP {self.config.num_str} ({self.config.name}): error log saved to {filepath}")
        except Exception as e:
            print(f"[NOC] Failed to save error log for IMP {self.config.num_str}: {e}")

    def _handle_unexpected_halt(self):
        """Handle unexpected entry to sim> prompt (not user-initiated).

        Saves error log and auto-restarts the IMP (unless debug_halts is set).
        """
        self._save_error_log()
        self._set_state(ProcessState.HALTED)

        if self.debug_halts:
            print(f"[NOC] IMP {self.config.num_str} ({self.config.name}): unexpected halt detected, log saved (debug mode - not restarting)")
        else:
            print(f"[NOC] IMP {self.config.num_str} ({self.config.name}): unexpected halt detected, saving log and restarting")
            self.send_reset()  # Auto-reboot via "do impXX.simh"

    def _handle_exit(self, status: int):
        """Handle process exit."""
        self._process = None
        self._set_state(ProcessState.CRASHED)

        # Check restart policy
        if self._restart_policy.should_restart():
            delay = self._restart_policy.get_delay()
            self._restart_policy.record_restart()
            # Schedule restart
            self.process_manager.loop.call_later(delay, self.start)


def parse_lights_value(octal_str: str) -> Dict[str, Any]:
    """Parse lights value into modem and host status.

    The lights value is an 18-bit octal number:
    - Bits 12-17 (high 6 bits): Modem status (1=dead, 0=alive for each modem line)
    - Bits 6-11 (middle 6 bits): Host status (1=dead, 0=alive for each host)
    - Bits 0-5 (low 6 bits): Other status bits

    Returns dict with 'modem_status', 'host_status', 'raw_value'
    """
    try:
        value = int(octal_str, 8)
    except ValueError:
        value = int(octal_str)

    modem_status = (value >> 12) & 0o77
    host_status = (value >> 6) & 0o77

    return {
        'raw_value': value,
        'modem_status': modem_status,
        'host_status': host_status,
        'modem_dead': [(modem_status >> i) & 1 for i in range(6)],
        'host_dead': [(host_status >> i) & 1 for i in range(6)],
    }
