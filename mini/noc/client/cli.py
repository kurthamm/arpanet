"""CLI command parsing and execution."""

import sys
import argparse
from typing import List, Optional

from .connection import NOCConnection
from .display import StatusDisplay
from .attach import attach_to_imp


class CLI:
    """Command-line interface for NOC client."""

    def __init__(self, socket_path: str = "/tmp/noc.sock"):
        self.socket_path = socket_path
        self.conn: Optional[NOCConnection] = None
        self.display = StatusDisplay(use_color=sys.stdout.isatty())

    def run(self, args: List[str]) -> int:
        """Run CLI with given arguments. Returns exit code."""
        parser = self._create_parser()
        opts = parser.parse_args(args)

        # Handle help without needing server connection
        if opts.command and opts.command.lower() == "help":
            return self._cmd_help([])

        # Use socket from options if specified
        if hasattr(opts, 'socket') and opts.socket:
            self.socket_path = opts.socket

        # Connect to server
        self.conn = NOCConnection(self.socket_path)
        if not self.conn.connect():
            print(f"Error: Cannot connect to NOC server at {self.socket_path}")
            print("Is noc-server.py running?")
            return 1

        try:
            if opts.follow:
                return self._follow_mode(opts.events)
            elif opts.command:
                return self._execute_command(opts.command, opts)
            else:
                # Default: show status
                return self._cmd_status([])
        finally:
            self.conn.disconnect()

    def _create_parser(self) -> argparse.ArgumentParser:
        """Create argument parser."""
        parser = argparse.ArgumentParser(
            prog="impctl",
            description="ARPANET Network Operations Center CLI"
        )

        parser.add_argument(
            "--socket", "-s",
            default="/tmp/noc.sock",
            help="Path to NOC server socket"
        )

        parser.add_argument(
            "--follow", "-f",
            action="store_true",
            help="Follow events (subscribe mode)"
        )

        parser.add_argument(
            "--events", "-e",
            default="all",
            help="Events to follow (comma-separated: lights,state,restart)"
        )

        parser.add_argument(
            "command",
            nargs="?",
            help="Command to execute"
        )

        parser.add_argument(
            "args",
            nargs="*",
            help="Command arguments"
        )

        return parser

    def _execute_command(self, command: str, opts) -> int:
        """Execute a single command."""
        cmd_args = opts.args if hasattr(opts, 'args') else []

        handlers = {
            "status": self._cmd_status,
            "lights": self._cmd_lights,
            "history": self._cmd_history,
            "attach": self._cmd_attach,
            "cont": self._cmd_cont,
            "reset": self._cmd_reset,
            "reboot": self._cmd_reboot,
            "restart": self._cmd_restart,
            "stop": self._cmd_stop,
            "start": self._cmd_start,
            "quit": self._cmd_quit,
            "help": self._cmd_help,
        }

        handler = handlers.get(command.lower())
        if handler is None:
            print(f"Unknown command: {command}")
            print("Use 'impctl help' for available commands")
            return 1

        return handler(cmd_args)

    def _cmd_status(self, args: List[str]) -> int:
        """Show status."""
        if args:
            # Single target
            response = self.conn.send_command("status", target=args[0])
        else:
            # Full status
            response = self.conn.send_command("status")

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        data = response.get("data", {})

        if "imp" in data:
            print(self.display.format_imp_detail(data))
        elif "ncp" in data:
            ncp = data["ncp"]
            print(f"NCP Host {ncp['host']:02d}: {ncp['name']}")
            print(f"  IMP:   {ncp['imp']:02d}")
            print(f"  State: {ncp['state']}")
            print(f"  PID:   {ncp.get('pid') or 'N/A'}")
        else:
            print(self.display.format_status_table(data))

        return 0

    def _cmd_lights(self, args: List[str]) -> int:
        """Show lights."""
        if args:
            response = self.conn.send_command("lights", target=args[0])
        else:
            response = self.conn.send_command("lights")

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        data = response.get("data", {})

        if "lights" in data and isinstance(data["lights"], dict):
            print(self.display.format_lights_table(data))
        else:
            print(f"IMP {data.get('imp', '?'):02d} ({data.get('name', '?')}): {data.get('lights', 'N/A')}")

        return 0

    def _cmd_history(self, args: List[str]) -> int:
        """Show lights history."""
        if not args:
            print("Usage: history <imp> [limit]")
            return 1

        target = args[0]
        limit = int(args[1]) if len(args) > 1 else 20

        response = self.conn.send_command("history", target=target, limit=limit)

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        print(self.display.format_history(response.get("data", {})))
        return 0

    def _cmd_attach(self, args: List[str]) -> int:
        """Attach to IMP."""
        if not args:
            print("Usage: attach <imp>")
            return 1

        if not sys.stdin.isatty():
            print("Error: attach requires a terminal")
            return 1

        return 0 if attach_to_imp(self.conn, args[0]) else 1

    def _cmd_cont(self, args: List[str]) -> int:
        """Continue halted IMPs."""
        target = args[0] if args else "halted"
        response = self.conn.send_command("cont", target=target)

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        continued = response.get("data", {}).get("continued", [])
        if continued:
            print(f"Continued: {', '.join(str(i) for i in continued)}")
        else:
            print("No IMPs needed continuing")
        return 0

    def _cmd_reset(self, args: List[str]) -> int:
        """Reset IMPs (reload SIMH script)."""
        if not args:
            print("Usage: reset <target>")
            return 1

        response = self.conn.send_command("reset", target=args[0])

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        reset = response.get("data", {}).get("reset", [])
        if reset:
            print(f"Reset: {', '.join(str(i) for i in reset)}")
        else:
            print("No IMPs were reset")
        return 0

    def _cmd_reboot(self, args: List[str]) -> int:
        """Reboot IMPs (alias for reset - reload SIMH script)."""
        if not args:
            print("Usage: reboot <target>")
            return 1

        response = self.conn.send_command("reboot", target=args[0])

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        rebooted = response.get("data", {}).get("reset", [])
        if rebooted:
            print(f"Rebooted: {', '.join(str(i) for i in rebooted)}")
        else:
            print("No IMPs were rebooted")
        return 0

    def _cmd_restart(self, args: List[str]) -> int:
        """Force restart IMPs."""
        if not args:
            print("Usage: restart <target>")
            return 1

        response = self.conn.send_command("restart", target=args[0])

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        restarted = response.get("data", {}).get("restarted", [])
        if restarted:
            print(f"Restarted: {', '.join(str(i) for i in restarted)}")
        restarted_ncps = response.get("data", {}).get("restarted_ncps", [])
        if restarted_ncps:
            print(f"Restarted NCPs: {', '.join(str(i) for i in restarted_ncps)}")
        return 0

    def _cmd_stop(self, args: List[str]) -> int:
        """Stop IMPs."""
        if not args:
            print("Usage: stop <target>")
            return 1

        response = self.conn.send_command("stop", target=args[0])

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        stopped = response.get("data", {}).get("stopped", [])
        if stopped:
            print(f"Stopped: {', '.join(str(i) for i in stopped)}")
        return 0

    def _cmd_start(self, args: List[str]) -> int:
        """Start stopped IMPs."""
        if not args:
            print("Usage: start <target>")
            return 1

        response = self.conn.send_command("start", target=args[0])

        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        started = response.get("data", {}).get("started", [])
        if started:
            print(f"Started: {', '.join(str(i) for i in started)}")
        return 0

    def _cmd_quit(self, args: List[str]) -> int:
        """Quit NOC server."""
        response = self.conn.send_command("quit")
        print("Shutdown initiated")
        return 0

    def _cmd_help(self, args: List[str]) -> int:
        """Show help."""
        print("""ARPANET Network Operations Center (NOC) CLI

Usage: impctl [options] [command] [args...]

Commands:
  status [target]      Show network status (default: all)
  lights [target]      Show current IMP lights
  history <imp> [n]    Show lights history (last n entries)
  attach <imp>         Attach to IMP console (Ctrl-] to detach)
  cont [target]        Continue halted IMPs (default: all halted)
  reboot <target>      Reboot IMP (reload SIMH script via "do impXX.simh")
  reset <target>       Alias for reboot
  restart <target>     Force restart IMP (kill and respawn h316ov process)
  stop <target>        Stop IMP (no auto-restart)
  start <target>       Start stopped IMP
  quit                 Shutdown NOC server and all processes
  help                 Show this help

Recovery options (escalating) - use IMP number/name or "halted"/"crashed":
  cont <target>        Resume simulation (IMP state preserved)
  reboot <target>      Reload SIMH script (fresh IMP boot, SIMH preserved)
  restart <target>     Kill and respawn process (fresh everything)
  Examples: cont 5, cont MIT, cont halted, reboot UCLA, restart crashed

Targets:
  <number>             Single IMP by number (e.g., 5, 05)
  <name>               Single IMP by name (e.g., UCLA, BBN)
  <list>               Comma-separated (e.g., 1,2,5)
  all                  All IMPs
  halted               All halted IMPs
  crashed              All crashed IMPs
  running              All running IMPs
  stopped              All stopped IMPs

Options:
  -f, --follow         Subscribe to events and display live
  -e, --events TYPES   Event types to follow (lights,state,restart,all)
  -s, --socket PATH    NOC server socket path (default: /tmp/noc.sock)

Examples:
  impctl                     Show full status
  impctl status 5            Show status of IMP 5
  impctl lights              Show all IMP lights
  impctl history UCLA 50     Show last 50 lights changes for UCLA
  impctl attach BBN          Attach to BBN IMP console
  impctl cont halted         Continue all halted IMPs
  impctl reboot halted       Reboot all halted IMPs
  impctl restart crashed     Restart all crashed IMPs
  impctl -f                  Follow all events
""")
        return 0

    def _follow_mode(self, events_str: str) -> int:
        """Run in follow mode, streaming events."""
        events = [e.strip() for e in events_str.split(",")]

        # Subscribe
        response = self.conn.subscribe(events)
        if not response.get("ok"):
            print(self.display.format_error(response.get("error", "Unknown error")))
            return 1

        print(f"Subscribed to: {', '.join(response.get('data', {}).get('subscribed', []))}")
        print("Press Ctrl+C to stop")
        print("-" * 40)

        try:
            while True:
                for event in self.conn.read_events(timeout=1.0):
                    if "event" in event:
                        print(self.display.format_event(event))
        except KeyboardInterrupt:
            print("\nStopped")

        return 0


def main():
    """Main entry point for impctl."""
    cli = CLI()
    sys.exit(cli.run(sys.argv[1:]))


if __name__ == "__main__":
    main()
