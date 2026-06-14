#!/usr/bin/env python3
"""NOC Server - Network Operations Center for ARPANET simulation.

This daemon supervises all IMP routers and NCP daemons, providing
monitoring and control via a Unix socket protocol.

Usage:
    ./noc-server.py              Start the server
    ./noc-server.py --config PATH  Use alternate arpanet script
"""

import sys
import os
import signal
import subprocess
import argparse
import time
import logging
from pathlib import Path
from typing import Dict, Optional

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from noc.config import parse_arpanet_script, IMPConfig, NCPConfig
from noc.protocol import ProcessState, EventType
from noc.server.eventloop import EventLoop
from noc.server.process import ProcessManager
from noc.server.imp import IMPController
from noc.server.ncp import NCPController
from noc.server.protocol import ClientHandler


class NOCServer:
    """Main NOC server class."""

    DEFAULT_CONFIG = "./arpanet"
    DEFAULT_SOCKET = "/tmp/noc.sock"
    LOGFILE = "./logfiles/noc.audit.log"
    # Some IMPs take about 30 seconds to reach RUNNING after a cold NOC
    # restart. Starting NCP daemons too early leaves source NCP sockets alive
    # but unable to pass traffic, so wait for the routers to settle.
    NCP_START_DELAY = 35.0

    def __init__(
        self,
        config_path: str = DEFAULT_CONFIG,
        socket_path: str = DEFAULT_SOCKET,
        debug_halts: bool = False,
    ):
        self.config_path = config_path
        self.socket_path = socket_path
        self.debug_halts = debug_halts
        self.working_dir = str(Path(__file__).parent.absolute())

        self.loop: Optional[EventLoop] = None
        self.process_manager: Optional[ProcessManager] = None
        self.client_handler: Optional[ClientHandler] = None

        self.imps: Dict[int, IMPController] = {}
        self.ncps: Dict[int, NCPController] = {}

        self._imp_configs = []
        self._ncp_configs = []
        self._shutting_down = False
        self._setup_logging()

    def _setup_logging(self):
        """Set up audit logging."""
        logdir = Path(self.working_dir) / "logfiles"
        logdir.mkdir(exist_ok=True)

        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s %(levelname)s %(message)s',
            handlers=[
                logging.FileHandler(logdir / "noc.audit.log"),
                logging.StreamHandler(sys.stdout),
            ]
        )
        self.logger = logging.getLogger("noc")

    def _load_config(self):
        """Load configuration from arpanet script."""
        config_file = Path(self.working_dir) / self.config_path
        self.logger.info(f"Loading configuration from {config_file}")

        self._imp_configs, self._ncp_configs = parse_arpanet_script(str(config_file))

        self.logger.info(f"Loaded {len(self._imp_configs)} IMPs, {len(self._ncp_configs)} NCPs")

    def _on_imp_state_change(
        self,
        imp: IMPController,
        old_state: ProcessState,
        new_state: ProcessState
    ):
        """Handle IMP state change."""
        self.logger.info(f"IMP {imp.config.num_str} ({imp.config.name}): {old_state.value} -> {new_state.value}")

        # Broadcast to clients
        if self.client_handler:
            self.client_handler.broadcast_event(
                EventType.STATE.value,
                imp=imp.config.number,
                old=old_state.value,
                new=new_state.value,
            )

    def _on_imp_lights_change(
        self,
        imp: IMPController,
        value: str,
        timestamp: float
    ):
        """Handle IMP lights change."""
        # Broadcast to clients (don't log every lights change)
        if self.client_handler:
            self.client_handler.broadcast_event(
                EventType.LIGHTS.value,
                imp=imp.config.number,
                value=value,
                timestamp=timestamp,
            )

    def _on_ncp_state_change(
        self,
        ncp: NCPController,
        old_state: ProcessState,
        new_state: ProcessState
    ):
        """Handle NCP state change."""
        self.logger.info(f"NCP {ncp.config.host_str} ({ncp.config.hostname}): {old_state.value} -> {new_state.value}")

    def _kill_rogue_processes(self):
        """Kill any leftover h316* or ncpd* processes from previous runs."""
        self.logger.info("Checking for rogue processes...")

        killed = 0
        for pattern in ['h316', 'ncpd']:
            try:
                result = subprocess.run(
                    ['pkill', '-9', '-f', f'^./{pattern}'],
                    capture_output=True
                )
                if result.returncode == 0:
                    self.logger.info(f"Killed rogue {pattern}* processes")
                    killed += 1
            except Exception as e:
                self.logger.warning(f"Error killing {pattern}* processes: {e}")

        if killed:
            time.sleep(0.5)  # Brief pause to let processes terminate

    def _start_imps(self):
        """Start all IMP processes."""
        self.logger.info("Starting IMP simulators...")

        for config in self._imp_configs:
            imp = IMPController(
                config=config,
                process_manager=self.process_manager,
                on_state_change=self._on_imp_state_change,
                on_lights_change=self._on_imp_lights_change,
                debug_halts=self.debug_halts,
            )
            self.imps[config.number] = imp
            imp.start()

        self.logger.info(f"Started {len(self.imps)} IMP simulators")

    def _start_ncps(self):
        """Start all NCP daemon processes."""
        self.logger.info("Starting NCP daemons...")

        for config in self._ncp_configs:
            ncp = NCPController(
                config=config,
                process_manager=self.process_manager,
                on_state_change=self._on_ncp_state_change,
            )
            self.ncps[config.full_host] = ncp
            ncp.start()

        self.logger.info(f"Started {len(self.ncps)} NCP daemons")

    def _schedule_ncp_start(self):
        """Schedule NCP start shortly after IMPs begin booting.

        The H316 host interfaces expect their host/NCP UDP peers to appear
        quickly. Waiting for every IMP to reach RUNNING can leave HI ports
        peerless long enough to trigger unrecoverable host-interface errors.
        """
        self.logger.info(f"Waiting {self.NCP_START_DELAY}s for IMPs to initialize...")
        self.loop.call_later(self.NCP_START_DELAY, self._start_ncps)

    def _handle_quit(self):
        """Handle quit command - graceful shutdown."""
        if self._shutting_down:
            return
        self._shutting_down = True

        self.logger.info("Shutdown requested, stopping all processes...")

        # Stop all NCPs first
        for ncp in self.ncps.values():
            ncp.stop()

        # Then stop all IMPs
        for imp in self.imps.values():
            imp.stop()

        # Schedule actual shutdown
        self.loop.call_later(1.0, self._do_shutdown)

    def _do_shutdown(self):
        """Perform final shutdown."""
        self.logger.info("Shutting down event loop...")
        self.loop.stop()

    def _handle_signal(self, sig: int):
        """Handle termination signals."""
        signame = signal.Signals(sig).name
        self.logger.info(f"Received {signame}")
        self._handle_quit()

    def run(self):
        """Run the NOC server."""
        os.chdir(self.working_dir)

        self.logger.info("=" * 60)
        self.logger.info("NOC Server starting")
        self.logger.info(f"Working directory: {self.working_dir}")
        self.logger.info(f"Socket path: {self.socket_path}")
        if self.debug_halts:
            self.logger.info("Debug mode: unexpected halts will NOT auto-restart")
        self.logger.info("=" * 60)

        # Load configuration
        self._load_config()

        # Initialize event loop
        self.loop = EventLoop()

        # Set up signal handlers
        self.loop.setup_signal_handler(signal.SIGTERM, self._handle_signal)
        self.loop.setup_signal_handler(signal.SIGINT, self._handle_signal)

        # Initialize process manager
        self.process_manager = ProcessManager(self.loop, self.working_dir)

        # Initialize client handler
        self.client_handler = ClientHandler(
            loop=self.loop,
            socket_path=self.socket_path,
            imps=self.imps,
            ncps=self.ncps,
            on_quit=self._handle_quit,
        )
        self.client_handler.start()

        self.logger.info(f"Listening on {self.socket_path}")

        # Kill any rogue processes from previous runs
        self._kill_rogue_processes()

        # Start IMPs
        self._start_imps()

        # Schedule NCP start
        self._schedule_ncp_start()

        # Run event loop
        try:
            self.loop.run()
        except Exception as e:
            self.logger.error(f"Event loop error: {e}")
        finally:
            self.logger.info("Cleaning up...")
            self.client_handler.stop()
            self.process_manager.close_all()
            self.loop.close()
            self.logger.info("NOC Server stopped")


def main():
    parser = argparse.ArgumentParser(
        description="NOC Server - Network Operations Center for ARPANET simulation"
    )
    parser.add_argument(
        "--config", "-c",
        default=NOCServer.DEFAULT_CONFIG,
        help="Path to arpanet configuration script"
    )
    parser.add_argument(
        "--socket", "-s",
        default=NOCServer.DEFAULT_SOCKET,
        help="Path to Unix socket for client connections"
    )
    parser.add_argument(
        "--debug-halts",
        action="store_true",
        help="Don't auto-restart IMPs that unexpectedly enter sim> prompt (for debugging)"
    )

    args = parser.parse_args()

    server = NOCServer(
        config_path=args.config,
        socket_path=args.socket,
        debug_halts=args.debug_halts,
    )
    server.run()


if __name__ == "__main__":
    main()
