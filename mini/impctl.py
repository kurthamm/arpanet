#!/usr/bin/env python3
"""impctl - ARPANET Network Operations Center CLI

A command-line interface for monitoring and controlling the simulated
1972 ARPANET network through the NOC server.

Usage:
    ./impctl                     Show full network status
    ./impctl status <imp>        Show single IMP status
    ./impctl lights              Show all IMP lights
    ./impctl history <imp>       Show lights history
    ./impctl attach <imp>        Attach to IMP console
    ./impctl cont [target]       Continue halted IMPs
    ./impctl restart <target>    Force restart IMPs
    ./impctl -f                  Follow events live
    ./impctl help                Show help

See 'impctl help' for full command reference.
"""

import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from noc.client.cli import main

if __name__ == "__main__":
    main()
