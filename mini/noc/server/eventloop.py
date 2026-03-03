"""Selector-based event loop for NOC server.

Handles I/O multiplexing for PTY file descriptors, Unix socket,
and client connections.
"""

import selectors
import signal
import os
import heapq
import time
from typing import Callable, Optional, Dict, Any, List, Tuple
from dataclasses import dataclass, field


@dataclass(order=True)
class TimerEntry:
    """A scheduled timer callback."""
    deadline: float
    callback: Callable[[], None] = field(compare=False)
    cancelled: bool = field(default=False, compare=False)


class EventLoop:
    """Selector-based event loop with timer support."""

    def __init__(self):
        self.selector = selectors.DefaultSelector()
        self._running = False
        self._timers: List[TimerEntry] = []
        self._wakeup_read, self._wakeup_write = os.pipe()
        self._pending_signals: List[int] = []

        # Set up wakeup pipe for signal handling
        os.set_blocking(self._wakeup_read, False)
        os.set_blocking(self._wakeup_write, False)
        self.selector.register(
            self._wakeup_read,
            selectors.EVENT_READ,
            (self._drain_wakeup, None)
        )

    def register(
        self,
        fd: int,
        events: int,
        callback: Callable[[int, int], None],
        data: Any = None
    ):
        """Register a file descriptor for events.

        Args:
            fd: File descriptor to monitor
            events: selectors.EVENT_READ and/or EVENT_WRITE
            callback: Called with (fd, events) when ready
            data: Optional data to associate with registration
        """
        self.selector.register(fd, events, (callback, data))

    def unregister(self, fd: int):
        """Unregister a file descriptor."""
        try:
            self.selector.unregister(fd)
        except (KeyError, ValueError):
            pass

    def modify(self, fd: int, events: int):
        """Modify events for a registered fd."""
        key = self.selector.get_key(fd)
        self.selector.modify(fd, events, key.data)

    def call_later(self, delay: float, callback: Callable[[], None]) -> TimerEntry:
        """Schedule a callback after delay seconds."""
        entry = TimerEntry(deadline=time.monotonic() + delay, callback=callback)
        heapq.heappush(self._timers, entry)
        return entry

    def call_at(self, when: float, callback: Callable[[], None]) -> TimerEntry:
        """Schedule a callback at a specific monotonic time."""
        entry = TimerEntry(deadline=when, callback=callback)
        heapq.heappush(self._timers, entry)
        return entry

    def cancel_timer(self, entry: TimerEntry):
        """Cancel a scheduled timer."""
        entry.cancelled = True

    def setup_signal_handler(self, sig: int, callback: Callable[[int], None]):
        """Set up a signal handler that integrates with the event loop.

        The callback will be called from the event loop, not the signal handler.
        """
        def handler(signum, frame):
            self._pending_signals.append(signum)
            # Wake up the event loop
            try:
                os.write(self._wakeup_write, b'\x00')
            except OSError:
                pass

        signal.signal(sig, handler)
        self._signal_callbacks = getattr(self, '_signal_callbacks', {})
        self._signal_callbacks[sig] = callback

    def _drain_wakeup(self, fd: int, events: int):
        """Drain the wakeup pipe and process pending signals."""
        try:
            os.read(self._wakeup_read, 1024)
        except OSError:
            pass

        # Process pending signals
        callbacks = getattr(self, '_signal_callbacks', {})
        while self._pending_signals:
            sig = self._pending_signals.pop(0)
            if sig in callbacks:
                callbacks[sig](sig)

    def _process_timers(self) -> Optional[float]:
        """Process expired timers and return timeout until next timer."""
        now = time.monotonic()

        while self._timers:
            entry = self._timers[0]
            if entry.cancelled:
                heapq.heappop(self._timers)
                continue
            if entry.deadline <= now:
                heapq.heappop(self._timers)
                entry.callback()
            else:
                return entry.deadline - now

        return None

    def run(self):
        """Run the event loop until stop() is called."""
        self._running = True

        while self._running:
            # Process timers and get timeout
            timeout = self._process_timers()

            # Wait for events
            try:
                events = self.selector.select(timeout=timeout)
            except InterruptedError:
                continue

            for key, mask in events:
                callback, data = key.data
                try:
                    callback(key.fd, mask)
                except Exception as e:
                    print(f"Error in callback for fd {key.fd}: {e}")

    def stop(self):
        """Stop the event loop."""
        self._running = False
        # Wake up select if blocked
        try:
            os.write(self._wakeup_write, b'\x00')
        except OSError:
            pass

    def close(self):
        """Close the event loop and release resources."""
        self.selector.close()
        os.close(self._wakeup_read)
        os.close(self._wakeup_write)
