"""NCP (Network Control Program) daemon controller."""

import os
import signal
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

    def _reap_stray_daemons(self):
        """Kill any live ncpdov already bound to THIS NCP's port pair.

        A PTY EOF/EIO on the daemon's master fd makes ProcessManager declare the
        process dead (_handle_pty_read -> _cleanup_process -> on_exit) even when
        the ncpdov is still running -- _handle_exit then nulls self._process, so
        the state/_process guards can no longer see the live daemon. A subsequent
        restart or re-fired IMP-RUNNING event would then spawn a SECOND ncpdov on
        the same ports (the observed ncp31 double-spawn on 20311/20312). Before we
        spawn, sweep /proc for any stray ncpdov holding our exact (tx,rx) pair and
        SIGKILL it, so there is ever only one daemon per NCP.
        """
        mine = self._process.pid if self._process else None
        tx, rx = str(self.config.tx_port), str(self.config.rx_port)
        try:
            pids = [p for p in os.listdir("/proc") if p.isdigit()]
        except OSError:
            return
        for pid_s in pids:
            pid = int(pid_s)
            if pid == mine:
                continue
            try:
                with open(f"/proc/{pid_s}/cmdline", "rb") as f:
                    parts = f.read().split(b"\0")
            except OSError:
                continue
            argv = [p.decode("utf-8", "replace") for p in parts if p]
            if not argv:
                continue
            if os.path.basename(argv[0]) != "ncpdov":
                continue
            # Match the exact port pair so we never touch another NCP's daemon.
            if tx in argv[1:] and rx in argv[1:]:
                try:
                    os.kill(pid, signal.SIGKILL)
                except OSError:
                    pass

    def start(self):
        """Start the NCP daemon."""
        if self._state not in (ProcessState.STOPPED, ProcessState.CRASHED):
            return

        # Guarantee exactly one ncpdov per NCP: clear any stray daemon left alive
        # by a false PTY-EOF before spawning a fresh one (see _reap_stray_daemons).
        self._reap_stray_daemons()

        self._set_state(ProcessState.STARTING)

        name = f"ncp{self.config.host_str}"
        args = [
            "./ncpdov",
            "localhost",
            str(self.config.tx_port),
            str(self.config.rx_port),
        ]

        # NCP daemon needs NCP environment variable for socket path
        env = {"NCP": f"{self.process_manager.working_dir}/ncp{self.config.host_str}"}

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
        else:
            self.start()

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
        # Log output for debugging
        log_path = os.path.join(
            self.process_manager.working_dir,
            "logfiles",
            f"ncp{self.config.host_str}.log"
        )
        with open(log_path, "ab") as f:
            f.write(data)

    def _handle_exit(self, status: int):
        """Handle process exit."""
        self._process = None
        self._set_state(ProcessState.CRASHED)

        # Check restart policy
        if self._restart_policy.should_restart():
            delay = self._restart_policy.get_delay()
            self._restart_policy.record_restart()
            self.process_manager.loop.call_later(delay, self.start)
