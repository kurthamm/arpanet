"""NCP (Network Control Program) daemon controller."""

import time
from typing import Optional, Callable, List
from dataclasses import dataclass

from ..config import NCPConfig
from ..protocol import ProcessState, NCPStatus
from .process import Process, ProcessManager
from .restart import RestartPolicy


class NCPController:
    """Controller for a single NCP daemon process.

    NCP daemons are simpler than IMPs - they just need to be running.
    State Machine:
        STOPPED ──[start()]──> STARTING ──[output]──> RUNNING
        ANY ──[exit/EOF]──> CRASHED
        CRASHED ──[restart policy]──> STARTING
    """

    def __init__(
        self,
        config: NCPConfig,
        process_manager: ProcessManager,
        on_state_change: Optional[Callable[['NCPController', ProcessState, ProcessState], None]] = None,
    ):
        self.config = config
        self.process_manager = process_manager
        self.on_state_change = on_state_change

        self._state = ProcessState.STOPPED
        self._process: Optional[Process] = None
        self._restart_policy = RestartPolicy()
        self._started_at: Optional[float] = None

    @property
    def state(self) -> ProcessState:
        """Current NCP state."""
        return self._state

    @property
    def pid(self) -> Optional[int]:
        """Process ID if running."""
        return self._process.pid if self._process else None

    @property
    def restart_count(self) -> int:
        """Number of restarts."""
        return self._restart_policy.restart_count

    def _set_state(self, new_state: ProcessState):
        """Change state and notify."""
        old_state = self._state
        if old_state != new_state:
            self._state = new_state
            if self.on_state_change:
                self.on_state_change(self, old_state, new_state)

    def start(self):
        """Start the NCP daemon."""
        if self._state not in (ProcessState.STOPPED, ProcessState.CRASHED):
            return

        self._set_state(ProcessState.STARTING)

        name = f"ncp{self.config.host_str}"
        args = [
            "./ncpdov",
            "localhost",
            str(self.config.tx_port),
            str(self.config.rx_port),
        ]

        # NCP daemon needs NCP environment variable for socket path
        env = {"NCP": f"{self.process_manager.working_dir}/ncp{self.config.full_host}"}

        self._process = self.process_manager.spawn(
            name=name,
            args=args,
            env=env,
            on_output=self._handle_output,
            on_exit=self._handle_exit,
        )

        self._started_at = time.time()

    def stop(self):
        """Stop the NCP daemon (no auto-restart)."""
        self._restart_policy.reset()
        self._restart_policy._restart_count = self._restart_policy.max_restarts
        if self._process:
            self.process_manager.kill(self._process)
        self._set_state(ProcessState.STOPPED)

    def force_restart(self):
        """Force restart, bypassing policy."""
        self._restart_policy.reset()
        if self._process:
            self.process_manager.kill(self._process)

    def get_status(self) -> NCPStatus:
        """Get current status."""
        return NCPStatus(
            host=self.config.full_host,
            name=self.config.hostname,
            imp=self.config.imp,
            state=self._state.value,
            pid=self.pid,
            restarts=self.restart_count,
        )

    def _handle_output(self, data: bytes):
        """Handle output from NCP daemon."""
        # Any output means it's running
        if self._state == ProcessState.STARTING:
            self._set_state(ProcessState.RUNNING)
            self._restart_policy.record_success()

    def _handle_exit(self, status: int):
        """Handle process exit."""
        self._process = None
        self._set_state(ProcessState.CRASHED)

        # Check restart policy
        if self._restart_policy.should_restart():
            delay = self._restart_policy.get_delay()
            self._restart_policy.record_restart()
            self.process_manager.loop.call_later(delay, self.start)
