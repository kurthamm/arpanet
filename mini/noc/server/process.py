"""PTY-based process management for NOC server.

Handles spawning, monitoring, and communicating with IMP and NCP processes.
"""

import os
import pty
import tty
import termios
import fcntl
import signal
import selectors
from typing import Callable, Optional, Dict, List, Any
from dataclasses import dataclass, field

from .eventloop import EventLoop


@dataclass
class Process:
    """A managed subprocess with PTY."""
    pid: int
    master_fd: int
    name: str
    args: List[str]
    cwd: str
    env: Dict[str, str]
    on_output: Optional[Callable[[bytes], None]] = None
    on_exit: Optional[Callable[[int], None]] = None


class ProcessManager:
    """Manages PTY-controlled subprocesses."""

    def __init__(self, loop: EventLoop, working_dir: str):
        self.loop = loop
        self.working_dir = working_dir
        self._processes: Dict[int, Process] = {}  # pid -> Process
        self._fd_to_pid: Dict[int, int] = {}       # master_fd -> pid
        self._pending_reaps: List[int] = []

        # Set up SIGCHLD handler
        loop.setup_signal_handler(signal.SIGCHLD, self._handle_sigchld)

    def spawn(
        self,
        name: str,
        args: List[str],
        cwd: Optional[str] = None,
        env: Optional[Dict[str, str]] = None,
        on_output: Optional[Callable[[bytes], None]] = None,
        on_exit: Optional[Callable[[int], None]] = None,
    ) -> Process:
        """Spawn a new process with PTY.

        Args:
            name: Identifier for the process
            args: Command and arguments (args[0] is the executable)
            cwd: Working directory (defaults to manager's working_dir)
            env: Environment variables to add to inherited environment
            on_output: Callback for process output
            on_exit: Callback for process exit (called with exit status)

        Returns:
            Process object
        """
        if cwd is None:
            cwd = self.working_dir

        # Create PTY
        master_fd, slave_fd = pty.openpty()

        # Set master to non-blocking
        flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
        fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

        # Build environment
        proc_env = os.environ.copy()
        if env:
            proc_env.update(env)

        pid = os.fork()

        if pid == 0:
            # Child process
            try:
                os.close(master_fd)
                os.setsid()

                # Set up slave as controlling terminal
                os.dup2(slave_fd, 0)
                os.dup2(slave_fd, 1)
                os.dup2(slave_fd, 2)
                if slave_fd > 2:
                    os.close(slave_fd)

                # Set terminal closer to raw mode but keep ECHO
                # This allows Ctrl-E to pass through while sim> prompt still echoes
                # Indices: 0=iflag, 1=oflag, 2=cflag, 3=lflag, 4=ispeed, 5=ospeed, 6=cc
                mode = termios.tcgetattr(0)
                # Disable flow control but keep ICRNL (CR to NL conversion for Enter key)
                mode[0] &= ~(termios.IXON | termios.IXOFF)
                # Disable ICANON (line buffering) and ISIG (signal chars) but KEEP ECHO
                mode[3] &= ~(termios.ICANON | termios.ISIG | termios.IEXTEN)
                mode[3] |= termios.ECHO  # Ensure ECHO is on
                # Set VMIN=1, VTIME=0 for immediate character availability
                mode[6][termios.VMIN] = 1
                mode[6][termios.VTIME] = 0
                termios.tcsetattr(0, termios.TCSANOW, mode)

                os.chdir(cwd)
                os.execvpe(args[0], args, proc_env)
            except Exception as e:
                os._exit(127)
        else:
            # Parent process
            os.close(slave_fd)

            proc = Process(
                pid=pid,
                master_fd=master_fd,
                name=name,
                args=args,
                cwd=cwd,
                env=proc_env,
                on_output=on_output,
                on_exit=on_exit,
            )

            self._processes[pid] = proc
            self._fd_to_pid[master_fd] = pid

            # Register for read events
            self.loop.register(
                master_fd,
                selectors.EVENT_READ,
                self._handle_pty_read
            )

            return proc

    def write(self, proc: Process, data: bytes):
        """Write data to a process's PTY."""
        try:
            os.write(proc.master_fd, data)
        except OSError as e:
            pass  # Process may have exited

    def terminate(self, proc: Process, sig: int = signal.SIGTERM):
        """Send a signal to a process."""
        try:
            os.kill(proc.pid, sig)
        except ProcessLookupError:
            pass

    def kill(self, proc: Process):
        """Forcefully kill a process."""
        self.terminate(proc, signal.SIGKILL)

    def get_process_by_name(self, name: str) -> Optional[Process]:
        """Find a process by name."""
        for proc in self._processes.values():
            if proc.name == name:
                return proc
        return None

    def get_process_by_pid(self, pid: int) -> Optional[Process]:
        """Find a process by PID."""
        return self._processes.get(pid)

    def _handle_pty_read(self, fd: int, events: int):
        """Handle data available on a PTY master."""
        pid = self._fd_to_pid.get(fd)
        if pid is None:
            return

        proc = self._processes.get(pid)
        if proc is None:
            return

        try:
            data = os.read(fd, 4096)
            if data and proc.on_output:
                proc.on_output(data)
            elif not data:
                # EOF - process closed the PTY
                self._cleanup_process(proc)
        except OSError as e:
            if e.errno == 5:  # EIO - PTY closed
                self._cleanup_process(proc)

    def _handle_sigchld(self, sig: int):
        """Handle SIGCHLD - reap zombie processes."""
        while True:
            try:
                pid, status = os.waitpid(-1, os.WNOHANG)
                if pid == 0:
                    break

                proc = self._processes.get(pid)
                if proc:
                    self._cleanup_process(proc, status)
            except ChildProcessError:
                break

    def _cleanup_process(self, proc: Process, status: int = -1):
        """Clean up a terminated process."""
        # Unregister from event loop
        self.loop.unregister(proc.master_fd)

        # Close PTY master
        try:
            os.close(proc.master_fd)
        except OSError:
            pass

        # Remove from tracking
        self._processes.pop(proc.pid, None)
        self._fd_to_pid.pop(proc.master_fd, None)

        # Call exit callback
        if proc.on_exit:
            proc.on_exit(status)

    def close_all(self):
        """Terminate and clean up all processes."""
        for proc in list(self._processes.values()):
            self.kill(proc)
