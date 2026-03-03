"""Restart policy with exponential backoff."""

import time
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class RestartPolicy:
    """Restart policy with exponential backoff.

    Tracks restart attempts and enforces backoff delays.
    """
    max_restarts: int = 5
    initial_delay: float = 1.0
    max_delay: float = 60.0
    backoff_factor: float = 2.0

    _restart_count: int = field(default=0, init=False)
    _last_restart: float = field(default=0.0, init=False)
    _next_delay: float = field(default=1.0, init=False)

    def should_restart(self) -> bool:
        """Check if we should attempt another restart."""
        return self._restart_count < self.max_restarts

    def get_delay(self) -> float:
        """Get the delay before next restart attempt."""
        return self._next_delay

    def record_restart(self):
        """Record that a restart is being attempted."""
        self._restart_count += 1
        self._last_restart = time.time()
        # Increase delay for next time
        self._next_delay = min(
            self._next_delay * self.backoff_factor,
            self.max_delay
        )

    def record_success(self):
        """Record that the process started successfully.

        Resets the backoff delay but keeps the restart count.
        """
        self._next_delay = self.initial_delay

    def reset(self):
        """Fully reset the policy (manual override)."""
        self._restart_count = 0
        self._next_delay = self.initial_delay

    @property
    def restart_count(self) -> int:
        """Number of restarts attempted."""
        return self._restart_count

    @property
    def last_restart(self) -> float:
        """Timestamp of last restart attempt."""
        return self._last_restart
